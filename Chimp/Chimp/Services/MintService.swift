/**
 * Mint Service
 * Handles the complete mint flow with NFC chip authentication
 */

import Foundation
import CoreNFC
import stellarsdk
import OSLog

/// Result of a successful mint operation
struct MintResult {
    let transactionHash: String
    let tokenId: UInt64
}

final class MintService {
    private let blockchainService = BlockchainService()
    private let walletService = WalletService.shared
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
            Logger.logError("Contract ID is empty", category: .blockchain)
            throw AppError.validation("Contract ID not configured. Please set the contract ID in settings.")
        }

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            Logger.logError("Invalid contract ID format: \(contractId)", category: .blockchain)
            Logger.logError("Contract ID should be 56 characters, start with 'C'", category: .blockchain)
            throw AppError.validation("Invalid contract ID format. Contract ID must be 56 characters and start with 'C'.")
        }

        Logger.logDebug("Contract ID: \(contractId)", category: .blockchain)
        Logger.logDebug("Contract ID length: \(contractId.count)", category: .blockchain)
        Logger.logDebug("Wallet address: \(wallet.address)", category: .blockchain)

        // Step 1: Read chip public key
        progressCallback?("Reading chip information...")
        let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)

        // Convert hex string to Data (65 bytes, uncompressed)
        guard let publicKeyData = Data(hexString: chipPublicKey),
              publicKeyData.count == 65,
              publicKeyData[0] == 0x04 else {
            throw AppError.crypto(.invalidKey("Invalid public key format from chip. Please ensure you're using a compatible NFC chip."))
        }

        // Use wallet address for read-only queries (no private key needed)
        let accountId = wallet.address
        Logger.logDebug("Source account: \(accountId)", category: .blockchain)

        // Step 2: Get nonce from contract (read-only, no private key needed)
        progressCallback?("Preparing transaction...")
        Logger.logDebug("Getting nonce for contract: \(config.contractId)", category: .blockchain)
        let currentNonce: UInt32
        do {
            currentNonce = try await blockchainService.getNonce(
                contractId: config.contractId,
                publicKey: publicKeyData,
                accountId: accountId
            )
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            Logger.logError("ERROR getting nonce: \(appError)", category: .blockchain)
            throw AppError.nfc(.chipError("Failed to get nonce: \(appError.localizedDescription)"))
        } catch {
            Logger.logError("ERROR getting nonce: \(error)", category: .blockchain)
            throw AppError.nfc(.chipError("Failed to get nonce: \(error.localizedDescription)"))
        }
        let nonce = currentNonce + 1
        Logger.logDebug("Using nonce: \(nonce)", category: .blockchain)

        // Step 4: Create SEP-53 message
        progressCallback?("Preparing transaction...")
        let (message, messageHash) = try CryptoUtils.createSEP53Message(
            contractId: config.contractId,
            functionName: "mint",
            args: [wallet.address],
            nonce: nonce,
            networkPassphrase: config.networkPassphrase
        )

        Logger.logDebug("SEP-53 message length: \(message.count)", category: .crypto)
        Logger.logDebug("SEP-53 message (hex): \(message.map { String(format: "%02x", $0) }.joined())", category: .crypto)
        Logger.logDebug("Message hash (hex): \(messageHash.map { String(format: "%02x", $0) }.joined())", category: .crypto)

        // Step 5: Sign with chip
        progressCallback?("Signing transaction...")
        let signatureComponents = try await ChipOperations.signWithChip(
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
        Logger.logDebug("Signature r (hex): \(rHex)", category: .crypto)
        Logger.logDebug("Signature s original (hex): \(sOriginalHex)", category: .crypto)
        Logger.logDebug("Signature s normalized (hex): \(sNormalizedHex)", category: .crypto)
        if originalS != normalizedS {
            Logger.logDebug("S value was normalized (s > half_order)", category: .crypto)
        } else {
            Logger.logDebug("S value already normalized (s <= half_order)", category: .crypto)
        }

        // Step 7: Build signature (r + normalized s) - 64 bytes total
        var signature = Data()
        signature.append(signatureComponents.r)
        signature.append(normalizedS)

        guard signature.count == 64 else {
            throw AppError.crypto(.invalidSignature)
        }

        let signatureHex = signature.map { String(format: "%02x", $0) }.joined()
        Logger.logDebug("Final signature (r+s, hex): \(signatureHex)", category: .crypto)

        // Step 8: Get keypair for transaction building and signing (requires biometric auth)
        let secureStorage = SecureKeyStorage()
        let sourceKeyPair = try secureStorage.withPrivateKey(reason: "Authenticate to sign the transaction", work: { key in
            try KeyPair(secretSeed: key)
        })
        
        // Step 9: Determine recovery ID offline
        progressCallback?("Preparing transaction...")
        Logger.logDebug("Determining recovery ID offline...", category: .blockchain)
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
            Logger.logDebug("Recovery ID determined: \(recoveryId)", category: .blockchain)
        } catch {
            Logger.logError("ERROR determining recovery ID: \(error)", category: .blockchain)
            throw AppError.crypto(.verificationFailed)
        }

        // Step 9: Build transaction with the correct recovery ID
        progressCallback?("Building transaction...")
        Logger.logDebug("Building transaction with recovery ID \(recoveryId)...", category: .blockchain)
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
            Logger.logInfo("Transaction built successfully, token ID: \(tokenId)", category: .blockchain)
        } catch let appError as AppError {
            // Re-throw contract errors as-is so ViewController can handle them specifically
            if case .blockchain(.contract) = appError {
                throw appError
            }
            Logger.logError("ERROR building transaction: \(appError)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to build transaction: \(appError.localizedDescription)"))
        } catch {
            Logger.logError("ERROR building transaction: \(error)", category: .blockchain)
            throw AppError.blockchain(.networkError("Failed to build transaction: \(error.localizedDescription)"))
        }

        // Step 10: Sign transaction
        progressCallback?("Signing transaction...")
        try await walletService.signTransaction(transaction)

        // Step 11: Submit transaction
        progressCallback?("Processing on blockchain network...")
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
        progressCallback?("Completing operation...")
        do {
            let newUrl = "https://nft.chimpdao.xyz/\(config.contractId)/\(tokenId)"
            try await NDEFReader.writeNDEFUrl(tag: tag, session: session, url: newUrl)
        } catch {
            Logger.logWarning("Failed to update NDEF data on chip: \(error)", category: .nfc)
            // Don't fail the mint operation if NDEF update fails - the token was successfully minted
        }

        return MintResult(transactionHash: txHash, tokenId: tokenId)
    }

}

