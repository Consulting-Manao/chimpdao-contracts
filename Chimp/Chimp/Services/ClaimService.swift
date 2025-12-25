/**
 * Claim Service
 * Handles the complete claim flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk

/// Result of a successful claim operation
struct ClaimResult {
    let transactionHash: String
    let tokenId: UInt64
}

class ClaimService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService()
    private let config = AppConfig.shared
    
    /// Execute claim flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Claim result with transaction hash and token ID
    /// - Throws: AppError if any step fails
    func executeClaim(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> ClaimResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }

        // Step 1: Read contract ID from chip's NDEF
        progressCallback?("Reading chip data...")
        let ndefUrl = try await readNDEFUrl(tag: tag, session: session)
        guard let ndefUrl = ndefUrl, let contractId = parseContractIdFromNDEFUrl(ndefUrl) else {
            throw AppError.validation("Invalid contract ID in NFC chip")
        }

        print("ClaimService: Contract ID from chip: \(contractId)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("ClaimService: ERROR: Invalid contract ID format: \(contractId)")
            print("ClaimService: Contract ID should be 56 characters, start with 'C'")
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }
        
        print("ClaimService: Contract ID: \(contractId)")
        print("ClaimService: Contract ID length: \(contractId.count)")
        print("ClaimService: Wallet address: \(wallet.address)")
        
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
            throw AppError.wallet(.keyLoadFailed)
        }
        let sourceKeyPair = try KeyPair(secretSeed: privateKey)
        print("ClaimService: Source account: \(sourceKeyPair.accountId)")
        
        // Step 3: Get nonce from contract
        progressCallback?("Getting nonce from contract...")
        print("ClaimService: Getting nonce for contract: \(config.contractId)")
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
            print("ClaimService: ERROR getting nonce: \(appError)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(appError.localizedDescription)"))
        } catch {
            print("ClaimService: ERROR getting nonce: \(error)")
            throw AppError.nfc(.chipError("Failed to get nonce: \(error.localizedDescription)"))
        }
        let nonce = currentNonce + 1
        print("ClaimService: Using nonce: \(nonce) (previous: \(currentNonce))")
        
        // Step 4: Create SEP-53 message
        progressCallback?("Creating authentication message...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "claim",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )
        
        print("ClaimService: SEP-53 message length: \(message.count)")
        print("ClaimService: SEP-53 message (hex): \(message.map { String(format: "%02x", $0) }.joined())")
        print("ClaimService: Message hash (hex): \(messageHash.map { String(format: "%02x", $0) }.joined())")
        
        // Step 4: Sign with chip
        progressCallback?("Signing with chip...")
        let signatureComponents = try await signWithChip(
            tag: tag,
            session: session,
            messageHash: messageHash,
            keyIndex: keyIndex
        )
        
        // Step 5: Normalize S value (required by Soroban's secp256k1_recover)
        // Matching JS implementation: normalizeS() in src/util/crypto.ts
        let originalS = signatureComponents.s
        let normalizedS = CryptoUtils.normalizeS(originalS)
        
        // Debug: Log signature components for comparison with JS
        let rHex = signatureComponents.r.map { String(format: "%02x", $0) }.joined()
        let sOriginalHex = originalS.map { String(format: "%02x", $0) }.joined()
        let sNormalizedHex = normalizedS.map { String(format: "%02x", $0) }.joined()
        print("ClaimService: Signature r (hex): \(rHex)")
        print("ClaimService: Signature s original (hex): \(sOriginalHex)")
        print("ClaimService: Signature s normalized (hex): \(sNormalizedHex)")
        if originalS != normalizedS {
            print("ClaimService: S value was normalized (s > half_order)")
        } else {
            print("ClaimService: S value already normalized (s <= half_order)")
        }
        
        // Step 6: Build signature (r + normalized s) - 64 bytes total
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)
        
        guard signature.count == 64 else {
            throw AppError.crypto(.invalidSignature)
        }
        
        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        print("ClaimService: Final signature (r+s, hex): \(signatureHex)")
        
        // Step 7: Determine recovery ID offline (matching JS determineRecoveryId)
        // This uses contract simulation to find the correct recovery ID before building the transaction
        // Note: Ideally this would use secp256k1 recovery (like JS @noble/secp256k1), but contract simulation works too
        progressCallback?("Determining recovery ID...")
        print("ClaimService: Determining recovery ID offline...")
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
            print("ClaimService: Recovery ID determined: \(recoveryId)")
        } catch {
            print("ClaimService: ERROR determining recovery ID: \(error)")
            throw AppError.crypto(.verificationFailed)
        }
        
        // Step 8: Build transaction with the correct recovery ID
        progressCallback?("Building transaction...")
        print("ClaimService: Building transaction with recovery ID \(recoveryId)...")
        let (transaction, tokenId): (Transaction, UInt64)
        do {
            (transaction, tokenId) = try await blockchainService.buildClaimTransaction(
                contractId: config.contractId,
                claimant: wallet.address,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceAccount: wallet.address,
                sourceKeyPair: sourceKeyPair
            )
            print("ClaimService: Transaction built successfully, token ID: \(tokenId)")
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            print("ClaimService: ERROR building transaction: \(appError)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(appError.localizedDescription)"))
        } catch {
            print("ClaimService: ERROR building transaction: \(error)")
            throw AppError.blockchain(.networkError("Failed to build transaction: \(error.localizedDescription)"))
        }

        // Step 9: Sign transaction
        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        // Step 10: Submit transaction (send the signed transaction object directly, matching test script)
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
            print("ClaimService: NDEF data updated successfully on chip")
        } catch {
            print("ClaimService: WARNING - Failed to update NDEF data on chip: \(error)")
            // Don't fail the claim operation if NDEF update fails - the token was successfully claimed
        }

        return ClaimResult(transactionHash: txHash, tokenId: tokenId)
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

    /// Parse contract ID from NDEF URL (extracts the contract ID part)
    private func parseContractIdFromNDEFUrl(_ url: String) -> String? {
        // Remove protocol if present
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }

        // Split by '/' and expect contract ID as second component
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return nil
        }

        let contractId = String(components[1])

        // Validate contract ID format
        guard contractId.count == 56 && contractId.hasPrefix("C") else {
            return nil
        }

        return contractId
    }

    // MARK: - NDEF Operations

    /// Read NDEF URL from chip using APDU commands
    private func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        print("ClaimService: Reading NDEF URL...")

        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF Application APDU"))
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)

            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)"))
            }
            print("ClaimService: NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            print("ClaimService: NDEF File selected")

            // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
            guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create READ NLEN APDU"))
            }
            let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)

            guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to read NLEN: \(readNlenSW1) \(readNlenSW2)"))
            }

            let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
            if nlen == 0 {
                print("ClaimService: No NDEF data (NLEN = 0)")
                return nil
            }

            print("ClaimService: NLEN = \(nlen) bytes")

            // Step 4: Read actual NDEF data (starting from offset 2)
            var ndefData = Data()
            var currentOffset: UInt16 = 2
            let maxReadLength: UInt8 = 255 - 2

            while ndefData.count < Int(nlen) {
                let bytesToRead = min(Int(nlen) - ndefData.count, Int(maxReadLength))

                guard let readBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xB0,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(bytesToRead)
                ])) else {
                    throw AppError.nfc(.readWriteFailed("Failed to create READ BINARY APDU"))
                }

                let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)

                guard readSW1 == 0x90 && readSW2 == 0x00 else {
                    throw AppError.nfc(.readWriteFailed("Failed to read NDEF data chunk: \(readSW1) \(readSW2)"))
                }

                ndefData.append(readData)
                currentOffset += UInt16(bytesToRead)
            }

            // Parse the NDEF URL
            return parseNDEFUrl(from: ndefData)

        } catch {
            print("ClaimService: Error reading NDEF: \(error)")
            throw error
        }
    }

    /// Parse NDEF URL record from raw data
    private func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 7 else {
            print("ClaimService: NDEF data too short")
            return nil
        }

        // Parse NDEF record
        let flags = data[0]
        let typeLength = data[1]
        let payloadLength = data[2]
        let typeStart = 3
        let payloadStart = typeStart + Int(typeLength)

        guard data.count >= payloadStart + Int(payloadLength) else {
            print("ClaimService: NDEF data truncated")
            return nil
        }

        let typeData = data.subdata(in: typeStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<payloadStart + Int(payloadLength))

        // Check if this is a URI record
        guard typeData.count == 1 && typeData[0] == 0x55 else { // URI record type
            print("ClaimService: Not a URI record")
            return nil
        }

        // Parse URI payload
        guard payloadData.count >= 1 else {
            print("ClaimService: URI payload too short")
            return nil
        }

        let uriIdentifierCode = payloadData[0]
        let uriData = payloadData.subdata(in: 1..<payloadData.count)

        // URI identifier codes (RFC 3986)
        let uriPrefixes = [
            "", // 0x00: no prefix
            "http://www.", // 0x01
            "https://www.", // 0x02
            "http://", // 0x03
            "https://", // 0x04
            "tel:", // 0x05
            "mailto:", // 0x06
            "ftp://anonymous:anonymous@", // 0x07
            "ftp://ftp.", // 0x08
            "ftps://", // 0x09
            "sftp://", // 0x0A
            "smb://", // 0x0B
            "nfs://", // 0x0C
            "ftp://", // 0x0D
            "dav://", // 0x0E
            "news:", // 0x0F
            "telnet://", // 0x10
            "imap:", // 0x11
            "rtsp://", // 0x12
            "urn:", // 0x13
            "pop:", // 0x14
            "sip:", // 0x15
            "sips:", // 0x16
            "tftp:", // 0x17
            "btspp://", // 0x18
            "btl2cap://", // 0x19
            "btgoep://", // 0x1A
            "tcpobex://", // 0x1B
            "irdaobex://", // 0x1C
            "file://", // 0x1D
            "urn:epc:id:", // 0x1E
            "urn:epc:tag:", // 0x1F
            "urn:epc:pat:", // 0x20
            "urn:epc:raw:", // 0x21
            "urn:epc:", // 0x22
            "urn:nfc:" // 0x23
        ]

        var prefix = ""
        if Int(uriIdentifierCode) < uriPrefixes.count {
            prefix = uriPrefixes[Int(uriIdentifierCode)]
        }

        guard let uriString = String(data: uriData, encoding: .utf8) else {
            print("ClaimService: Failed to decode URI string")
            return nil
        }

        let fullUrl = prefix + uriString
        print("ClaimService: Successfully parsed NDEF URL: \(fullUrl)")
        return fullUrl
    }

    /// NDEF Application ID
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// NDEF File ID
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]

    /// Update NDEF data on chip with token ID
    private func updateNDEFOnChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, tokenId: UInt64) async throws {
        print("ClaimService: Updating NDEF data on chip with token ID: \(tokenId)")

        // Construct new NDEF URL with token ID
        let contractId = config.contractId
        let newUrl = "https://nft.chimpdao.xyz/\(contractId)/\(tokenId)"
        print("ClaimService: New NDEF URL: \(newUrl)")

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
            print("ClaimService: NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            print("ClaimService: NDEF File selected")

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
            print("ClaimService: NLEN written: \(nlen)")

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

            print("ClaimService: NDEF data written successfully")
        } catch {
            print("ClaimService: Error updating NDEF: \(error)")
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

