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
        
        let contractId = config.contractId
        guard !contractId.isEmpty else {
            print("ClaimService: ERROR: Contract ID is empty")
            throw AppError.validation("Contract ID not configured. Please set the contract ID in settings.")
        }
        
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
}

