/**
 * Mint Service
 * Handles the complete mint flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk

/// Result of a successful mint operation
struct MintResult {
    let transactionHash: String
    let tokenId: UInt64
}

class MintService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService()
    private let config = AppConfig.shared

    /// Execute mint flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Mint result with transaction hash and token ID
    /// - Throws: AppError if any step fails
    func executeMint(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> MintResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }

        let contractId = config.contractId
        guard !contractId.isEmpty else {
            print("MintService: ERROR: Contract ID is empty")
            throw AppError.validation("Contract ID not configured. Please set the contract ID in settings.")
        }

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("MintService: ERROR: Invalid contract ID format: \(contractId)")
            print("MintService: Contract ID should be 56 characters, start with 'C'")
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        print("MintService: Contract ID: \(contractId)")
        print("MintService: Contract ID length: \(contractId.count)")
        print("MintService: Wallet address: \(wallet.address)")

        // Step 1: Read chip public key
        progressCallback?("Reading chip public key...")
        let chipPublicKey = try await readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }

        // Step 2: Get source keypair for transaction building
        let secureStorage = SecureKeyStorage()
        guard let privateKey = try secureStorage.loadPrivateKey() else {
            throw AppError.wallet(.noWallet)
        }
        let sourceKeyPair = try KeyPair(secretSeed: privateKey)
        print("MintService: Source account: \(sourceKeyPair.accountId)")

        // Step 3: Get nonce from contract
        progressCallback?("Getting nonce from contract...")
        print("MintService: Getting nonce for contract: \(config.contractId)")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
                publicKey: publicKeyData,
                sourceKeyPair: sourceKeyPair
            )
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            print("MintService: ERROR getting nonce: \(appError)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(appError.localizedDescription)"))
        } catch {
            print("MintService: ERROR getting nonce: \(error)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(error.localizedDescription)"))
        }
        let nonce = currentNonce + 1
        print("MintService: Using nonce: \(nonce)")

        // Step 4: Create SEP-53 message
        progressCallback?("Creating authentication message...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "mint",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        print("MintService: SEP-53 message length: \(message.count)")
        print("MintService: SEP-53 message (hex): \(message.map { String(format: "%02x", $0) }.joined())")
        print("MintService: Message hash (hex): \(messageHash.map { String(format: "%02x", $0) }.joined())")

        // Step 5: Sign with chip
        progressCallback?("Signing with chip...")
        let signatureComponents = try await signWithChip(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )

        // Step 6: Normalize S value (required by Soroban's secp256k1_recover)
        let originalS = signatureComponents.s
        let normalizedS = CryptoUtils.normalizeS(originalS)

        // Debug: Log signature components
        let rHex = signatureComponents.r.map { String(format: "%02x", $0) }.joined()
        let sOriginalHex = originalS.map { String(format: "%02x", $0) }.joined()
        let sNormalizedHex = normalizedS.map { String(format: "%02x", $0) }.joined()
        print("MintService: Signature r (hex): \(rHex)")
        print("MintService: Signature s original (hex): \(sOriginalHex)")
        print("MintService: Signature s normalized (hex): \(sNormalizedHex)")
        if originalS != normalizedS {
            print("MintService: S value was normalized (s > half_order)")
        } else {
            print("MintService: S value already normalized (s <= half_order)")
        }

        // Step 7: Build signature (r + normalized s) - 64 bytes total
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)

        guard signature.count == 64 else {
            throw AppError.crypto(.invalidSignature)
        }

        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        print("MintService: Final signature (r+s, hex): \(signatureHex)")

        // Step 8: Determine recovery ID offline
        progressCallback?("Determining recovery ID...")
        print("MintService: Determining recovery ID offline...")
        let recoveryId: UInt32
        do {
            recoveryId = try await blockchainService.determineRecoveryId(
                contractId: config.contractId,
                claimant: wallet.address,
                message: message,
                signature: signature,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
            print("MintService: Recovery ID determined: \(recoveryId)")
        } catch {
            print("MintService: ERROR determining recovery ID: \(error)")
            throw AppError.crypto(.verificationFailed)
        }

        // Step 9: Build transaction with the correct recovery ID
        progressCallback?("Building transaction...")
        print("MintService: Building transaction with recovery ID \(recoveryId)...")
        let (transaction, tokenId): (Transaction, UInt64)
        do {
            (transaction, tokenId) = try await blockchainService.buildMintTransaction(
                contractId: config.contractId,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
            print("MintService: Transaction built successfully, token ID: \(tokenId)")
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            print("MintService: ERROR building transaction: \(appError)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(appError.localizedDescription)"))
        } catch {
            print("MintService: ERROR building transaction: \(error)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(error.localizedDescription)"))
        }

        // Step 10: Sign transaction
        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        // Step 11: Submit transaction
        progressCallback?("Submitting transaction...")
        let txHash: String
        do {
            txHash = try await blockchainService.submitTransaction(transaction, progressCallback: progressCallback)
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(appError.localizedDescription)"))
        } catch {
            throw AppError.blockchain(.networkError("Failed to submit transaction: \(error.localizedDescription)"))
        }

        // Step 12: Update NDEF data on chip with token ID
        progressCallback?("Updating chip data...")
        do {
            try await updateNDEFOnChip(tag: tag, session: session, tokenId: tokenId)
            print("MintService: NDEF data updated successfully on chip")
        } catch {
            print("MintService: WARNING - Failed to update NDEF data on chip: \(error)")
            // Don't fail the mint operation if NDEF update fails - the token was successfully minted
        }

        return MintResult(transactionHash: txHash, tokenId: tokenId)
    }

    /// Read public key from chip
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGetKey(key_index: keyIndex) { success, response, error, session in
                if success, let response = response, response.count >= 73 {
                    // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
                    let publicKeyData = response.subdata(in: 9..<73) // 64 bytes of public key
                    // Add 0x04 prefix for uncompressed format
                    var fullPublicKey = Data([0x04])
                    fullPublicKey.append(publicKeyData)
                    let publicKeyHex = fullPublicKey.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: publicKeyHex)
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }

    /// Sign message with chip
    private func signWithChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, messageHash: Data, keyIndex: UInt8) async throws -> SignatureComponents {
        guard messageHash.count == 32 else {
            throw AppError.crypto(.invalidOperation("Invalid message hash. This is an internal error. Please try again."))
        }

        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGenerateSignature(key_index: keyIndex, message_digest: messageHash) { success, response, error, session in
                if success, let response = response, response.count >= 8 {
                    // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
                    let derSignature = response.subdata(in: 8..<response.count)

                    do {
                        let components = try DERSignatureParser.parse(derSignature)
                        continuation.resume(returning: components)
                    } catch {
                        continuation.resume(throwing: AppError.derSignature(.parseFailed(error.localizedDescription)))
                    }
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }

    // MARK: - NDEF Operations

    /// NDEF Application ID
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// NDEF File ID
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]

    /// Update NDEF data on chip with token ID
    private func updateNDEFOnChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, tokenId: UInt64) async throws {
        print("MintService: Updating NDEF data on chip with token ID: \(tokenId)")

        // Construct new NDEF URL with token ID
        let contractId = config.contractId
        let newUrl = "https://nft.chimpdao.xyz/\(contractId)/\(tokenId)"
        print("MintService: New NDEF URL: \(newUrl)")

        // Convert URL to NDEF record bytes
        guard let ndefBytes = createNDEFRecord(for: newUrl) else {
            throw AppError.nfc(.readWriteFailed("Failed to create NDEF record"))
        }

        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF Application APDU"))
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)

            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)"))
            }
            print("MintService: NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            print("MintService: NDEF File selected")

            // Step 3: Write NLEN (NDEF message length)
            let nlen = UInt16(ndefBytes.count)
            let nlenBytes = [UInt8((nlen >> 8) & 0xFF), UInt8(nlen & 0xFF)]
            guard let writeNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xD6, 0x00, 0x00, 0x02] + nlenBytes)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create WRITE NLEN APDU"))
            }
            let (_, writeNlenSW1, writeNlenSW2) = try await tag.sendCommand(apdu: writeNlenAPDU)

            guard writeNlenSW1 == 0x90 && writeNlenSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to write NLEN: \(writeNlenSW1) \(writeNlenSW2)"))
            }
            print("MintService: NLEN written: \(nlen)")

            // Step 4: Write NDEF data (starting from offset 2)
            var currentOffset: UInt16 = 2
            let maxWriteLength: UInt8 = 255 - 2

            for chunkStart in stride(from: 0, to: ndefBytes.count, by: Int(maxWriteLength)) {
                let chunkEnd = min(chunkStart + Int(maxWriteLength), ndefBytes.count)
                let chunk = ndefBytes[chunkStart..<chunkEnd]

                guard let updateBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xD6,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(chunk.count)
                ] + Array(chunk))) else {
                    throw AppError.nfc(.readWriteFailed("Failed to create UPDATE BINARY APDU"))
                }

                let (_, writeSW1, writeSW2) = try await tag.sendCommand(apdu: updateBinaryAPDU)

                guard writeSW1 == 0x90 && writeSW2 == 0x00 else {
                    throw AppError.nfc(.readWriteFailed("Failed to write NDEF chunk at offset \(currentOffset): \(writeSW1) \(writeSW2)"))
                }

                currentOffset += UInt16(chunk.count)
            }

            print("MintService: NDEF data written successfully")
        } catch {
            print("MintService: Error updating NDEF: \(error)")
            throw error
        }
    }

    /// Create NDEF URI record from URL string
    private func createNDEFRecord(for url: String) -> Data? {
        guard let urlData = url.data(using: .utf8) else { return nil }

        // NDEF URI record format:
        // 0xD1 (MB=1, ME=1, CF=0, SR=1, IL=0, TNF=1) - URI record
        // 0x01 (Type length = 1)
        // Payload length (1 byte since SR=1)
        // 0x55 (Type = 'U' for URI)
        // Identifier code (0x00 = no prefix)
        // URI data

        let payloadLength = 1 + urlData.count // identifier code + url
        let recordLength = 1 + 1 + 1 + 1 + payloadLength // header + type length + payload length + type + payload

        var record = Data()
        record.append(0xD1) // TNF=URI, SR=1, ME=1, MB=1
        record.append(0x01) // Type length
        record.append(UInt8(payloadLength)) // Payload length
        record.append(0x55) // Type 'U'
        record.append(0x00) // No URI prefix
        record.append(urlData)

        return record
    }
}

