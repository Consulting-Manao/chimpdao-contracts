/**
 * Transfer Service
 * Handles the complete transfer flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk

/// Result of a successful transfer operation
struct TransferResult {
    let transactionHash: String
}

class TransferService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService()
    private let config = AppConfig.shared

    /// Execute transfer flow
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    ///   - recipientAddress: Address to transfer the token to
    ///   - tokenId: Token ID to transfer
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Transfer result with transaction hash
    /// - Throws: TransferError if any step fails
    func executeTransfer(
        tag: NFCISO7816Tag,
        session: NFCTagReaderSession,
        keyIndex: UInt8 = 0x01,
        recipientAddress: String,
        tokenId: UInt64,
        progressCallback: ((String) -> Void)? = nil
    ) async throws -> TransferResult {
        guard let wallet = walletService.getStoredWallet() else {
            throw TransferError.noWallet
        }

        let contractId = config.contractId
        guard !contractId.isEmpty else {
            print("TransferService: ERROR: Contract ID is empty")
            throw TransferError.noContractId
        }

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("TransferService: ERROR: Invalid contract ID format: \(contractId)")
            print("TransferService: Contract ID should be 56 characters, start with 'C'")
            throw TransferError.invalidContractId("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        // Validate recipient address
        guard config.validateStellarAddress(recipientAddress) else {
            print("TransferService: ERROR: Invalid recipient address: \(recipientAddress)")
            throw TransferError.invalidRecipientAddress
        }

        print("TransferService: Contract ID: \(contractId)")
        print("TransferService: Contract ID length: \(contractId.count)")
        print("TransferService: Wallet address: \(wallet.address)")
        print("TransferService: Recipient address: \(recipientAddress)")
        print("TransferService: Token ID: \(tokenId)")

        // Step 1: Read chip public key
        progressCallback?("Reading chip public key...")
        let chipPublicKey = try await readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw TransferError.invalidPublicKey
        }

        // Step 2: Get source keypair for transaction building
        let secureStorage = SecureKeyStorage()
        guard let privateKey = try secureStorage.loadPrivateKey() else {
            throw TransferError.noWallet
        }
        let sourceKeyPair = try KeyPair(secretSeed: privateKey)
        print("TransferService: Source account: \(sourceKeyPair.accountId)")

        // Step 3: Get nonce from contract
        progressCallback?("Getting nonce from contract...")
        print("TransferService: Getting nonce for contract: \(config.contractId)")
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
                publicKey: publicKeyData,
                sourceKeyPair: sourceKeyPair
            )
        } catch {
            print("TransferService: ERROR getting nonce: \(error)")
            throw TransferError.nonceRetrievalFailed("Failed to get nonce: \(error.localizedDescription)")
        }
        let nonce = currentNonce + 1
        print("TransferService: Using nonce: \(nonce) (previous: \(currentNonce))")

        // Step 4: Create SEP-53 message
        progressCallback?("Creating authentication message...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "transfer",
            args: [wallet.address, recipientAddress, String(tokenId)],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        print("TransferService: SEP-53 message length: \(message.count)")
        print("TransferService: SEP-53 message (hex): \(message.map { String(format: "%02x", $0) }.joined())")
        print("TransferService: Message hash (hex): \(messageHash.map { String(format: "%02x", $0) }.joined())")

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
        print("TransferService: Signature r (hex): \(rHex)")
        print("TransferService: Signature s original (hex): \(sOriginalHex)")
        print("TransferService: Signature s normalized (hex): \(sNormalizedHex)")
        if originalS != normalizedS {
            print("TransferService: S value was normalized (s > half_order)")
        } else {
            print("TransferService: S value already normalized (s <= half_order)")
        }

        // Step 7: Build signature (r + normalized s) - 64 bytes total
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)

        guard signature.count == 64 else {
            throw TransferError.invalidSignature
        }

        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        print("TransferService: Final signature (r+s, hex): \(signatureHex)")

        // Step 8: Determine recovery ID offline
        progressCallback?("Determining recovery ID...")
        print("TransferService: Determining recovery ID offline...")
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
            print("TransferService: Recovery ID determined: \(recoveryId)")
        } catch {
            print("TransferService: ERROR determining recovery ID: \(error)")
            throw TransferError.invalidRecoveryId("Could not determine recovery ID: \(error.localizedDescription)")
        }

        // Step 9: Build transaction with the correct recovery ID
        progressCallback?("Building transaction...")
        print("TransferService: Building transaction with recovery ID \(recoveryId)...")
        let transaction: Transaction
        do {
            transaction = try await blockchainService.buildTransferTransaction(
                contractId: config.contractId,
                from: wallet.address,
                to: recipientAddress,
                tokenId: tokenId,
                message: message,
                signature: signature,
                recoveryId: recoveryId,
                publicKey: publicKeyData,
                nonce: nonce,
                sourceKeyPair: sourceKeyPair
            )
            print("TransferService: Transaction built successfully")
        } catch {
            print("TransferService: ERROR building transaction: \(error)")
            throw TransferError.transactionBuildFailed("Failed to build transaction: \(error.localizedDescription)")
        }

        // Step 10: Sign transaction
        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        // Step 11: Submit transaction
        progressCallback?("Submitting transaction...")
        let txHash = try await blockchainService.submitTransaction(transaction, progressCallback: progressCallback)

        return TransferResult(transactionHash: txHash)
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
                    continuation.resume(throwing: TransferError.chipReadFailed(error ?? "Unknown error"))
                }
            }
        }
    }

    /// Sign message with chip
    private func signWithChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, messageHash: Data, keyIndex: UInt8) async throws -> SignatureComponents {
        guard messageHash.count == 32 else {
            throw TransferError.invalidMessageHash
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
                        continuation.resume(throwing: TransferError.signatureParseFailed(error.localizedDescription))
                    }
                } else {
                    continuation.resume(throwing: TransferError.chipSignFailed(error ?? "Unknown error"))
                }
            }
        }
    }
}

enum TransferError: Error, LocalizedError {
    case noWallet
    case noContractId
    case invalidContractId(String)
    case invalidRecipientAddress
    case invalidPublicKey
    case invalidMessageHash
    case nonceRetrievalFailed(String)
    case chipReadFailed(String)
    case chipSignFailed(String)
    case signatureParseFailed(String)
    case invalidSignature
    case invalidRecoveryId(String)
    case transactionBuildFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet configured. Please login with your secret key first."
        case .noContractId:
            return "Contract ID not configured. Please set the contract ID in settings."
        case .invalidContractId(let message):
            return message
        case .invalidRecipientAddress:
            return "Invalid recipient address. Please enter a valid Stellar address."
        case .invalidPublicKey:
            return "Invalid public key format from chip. Please ensure you're using a compatible NFC chip."
        case .invalidMessageHash:
            return "Invalid message hash. This is an internal error. Please try again."
        case .nonceRetrievalFailed(let message):
            return "Failed to get nonce: \(message). Please try again."
        case .chipReadFailed(let message):
            return "Failed to read from NFC chip: \(message). Please ensure the chip is held steady near the top of your device."
        case .chipSignFailed(let message):
            return "Failed to sign with NFC chip: \(message). Please ensure the chip is held steady and try again."
        case .signatureParseFailed(let message):
            return "Failed to parse signature from chip: \(message). Please try again."
        case .invalidSignature:
            return "Invalid signature format. Please try again."
        case .invalidRecoveryId(let message):
            return "Could not verify signature: \(message). Please ensure the NFC chip is working correctly."
        case .transactionBuildFailed(let message):
            return "Failed to build transaction: \(message). Please try again."
        }
    }
}
