/**
 * NFC Manager
 */

import Foundation
import CoreNFC
import stellarsdk
import OSLog

final class NFCManager {
    private let walletService = WalletService.shared
    private let nftService = NFTService()
    private let blockchainService = BlockchainService()

    private var nfcHelper: NFCHelper?
    
    // MARK: - Generic NFC Session Handler
    
    /// Generic NFC operation handler
    private func performNFCOperation<T>(
        guardChecks: () throws -> Void = {},
        operation: @escaping (NFCISO7816Tag, NFCTagReaderSession) async throws -> T,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        // Execute guard checks
        do {
            try guardChecks()
        } catch {
            completion(.failure(error))
            return
        }
        
        // Check NFC availability
        guard NFCTagReaderSession.readingAvailable else {
            completion(.failure(AppError.nfc(.notAvailable)))
            return
        }

        nfcHelper = NFCHelper()
        nfcHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            
            if success, let tag = tag, let session = session {
                // Update UI on main thread
                Task { @MainActor in
                    session.alertMessage = "Processing..."
                }
                
                // Execute operation on background thread
                Task.detached {
                    do {
                        let result = try await operation(tag, session)
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "Operation completed!"
                            session.invalidate()
                            completion(.success(result))
                            self.nfcHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Operation failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(.failure(error))
                            self.nfcHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(.failure(AppError.nfc(.readWriteFailed(errorMsg))))
                self.nfcHelper = nil
            }
        }

        nfcHelper?.BeginSession()
    }

    /// Load NFT - reads NDEF and gets token ID
    func loadNFT(completion: @escaping (Bool, String?, String?, UInt64?) -> Void) {
        performNFCOperation(
            guardChecks: {
                guard walletService.getStoredWallet() != nil else {
                    throw AppError.wallet(.noWallet)
                }
            },
            operation: { tag, session in
                // SAME loadNFT logic: NDEFReader + getTokenIdForChip
                await MainActor.run {
                    session.alertMessage = "Reading chip information..."
                }
                
                // Read NDEF to get contract ID
                let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
                guard let ndefUrl = ndefUrl else {
                    throw AppError.nfc(.readWriteFailed("No NDEF URL found"))
                }
                
                guard let contractId = NDEFReader.parseContractIdFromNDEFUrl(ndefUrl) else {
                    throw AppError.validation("Invalid contract ID in NFC tag")
                }
                
                // Read chip public key
                let chipPublicKey = try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: 0x01)
                guard let publicKeyData = Data(hexString: chipPublicKey) else {
                    throw AppError.crypto(.invalidKey("Invalid public key format from chip"))
                }
                
                await MainActor.run {
                    session.alertMessage = "Reading chip information..."
                }
                
                // Get token ID (this needs to happen while session is active for proper flow)
                let tokenId = try await self.getTokenIdForChip(contractId: contractId, publicKey: publicKeyData)
                
                return (contractId, tokenId)
            }
        ) { result in
            switch result {
            case .success(let (contractId, tokenId)):
                completion(true, nil, contractId, tokenId)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT"
                completion(false, errorMessage, nil, nil)
            }
        }
    }
    
    /// Claim NFT
    func claimNFT(completion: @escaping (Bool, String?, UInt64?, String?) -> Void) {
        performNFCOperation(
            guardChecks: {
                guard walletService.getStoredWallet() != nil else {
                    throw AppError.wallet(.noWallet)
                }
            },
            operation: { tag, session in
                // SAME claimNFT logic: nftService.executeClaim
                await MainActor.run {
                    session.alertMessage = "Preparing to claim NFT..."
                }
                
                let claimResult = try await self.nftService.executeClaim(
                    tag: tag,
                    session: session,
                    keyIndex: 0x01
                ) { progress in
                    Task { @MainActor in
                        session.alertMessage = progress
                    }
                }
                
                return claimResult
            }
        ) { result in
            switch result {
            case .success(let claimResult):
                completion(true, nil, claimResult.tokenId, claimResult.contractId)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Claim failed"
                completion(false, errorMessage, nil, nil)
            }
        }
    }
    
    /// Transfer NFT
    func transferNFT(recipientAddress: String, tokenId: UInt64, completion: @escaping (Bool, String?) -> Void) {
        performNFCOperation(
            guardChecks: {
                guard walletService.getStoredWallet() != nil else {
                    throw AppError.wallet(.noWallet)
                }
            },
            operation: { tag, session in
                await MainActor.run {
                    session.alertMessage = "Preparing to transfer NFT..."
                }
                
                let transferResult = try await self.nftService.executeTransfer(
                    tag: tag,
                    session: session,
                    keyIndex: 0x01,
                    recipientAddress: recipientAddress,
                    tokenId: tokenId
                ) { progress in
                    Task { @MainActor in
                        session.alertMessage = progress
                    }
                }
                
                return transferResult
            }
        ) { result in
            switch result {
            case .success(_):
                completion(true, nil)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Transfer failed"
                completion(false, errorMessage)
            }
        }
    }
    
    /// Read NFT for Transfer - reads NDEF to get token ID
    func readNFTForTransfer(completion: @escaping (Bool, UInt64?, String?) -> Void) {
        performNFCOperation(
            guardChecks: {
                guard walletService.getStoredWallet() != nil else {
                    throw AppError.wallet(.noWallet)
                }
            },
            operation: { tag, session in
                await MainActor.run {
                    session.alertMessage = "Reading chip information..."
                }
                
                // Read NDEF to get contract ID and token ID
                let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
                guard let ndefUrl = ndefUrl else {
                    throw AppError.validation("No NDEF data found on chip")
                }
                
                let tokenId = NDEFReader.parseTokenIdFromNDEFUrl(ndefUrl)
                guard let tokenId = tokenId else {
                    throw AppError.validation("Token ID not found on chip. This NFT may not be claimed yet.")
                }
                
                return tokenId
            }
        ) { result in
            switch result {
            case .success(let tokenId):
                completion(true, tokenId, nil)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to read chip. Please try again."
                completion(false, nil, errorMessage)
            }
        }
    }
    
    /// Mint NFT
    func mintNFT(completion: @escaping (Bool, String?, UInt64?) -> Void) {
        performNFCOperation(
            guardChecks: {
                guard walletService.getStoredWallet() != nil else {
                    throw AppError.wallet(.noWallet)
                }
                
                guard !AppConfig.shared.contractId.isEmpty else {
                    throw AppError.validation("Please set the contract ID in Settings")
                }
                
                guard AppConfig.shared.isAdminMode else {
                    throw AppError.validation("Admin mode required for minting")
                }
            },
            operation: { tag, session in
                // SAME mintNFT logic: nftService.executeMint
                await MainActor.run {
                    session.alertMessage = "Preparing to mint NFT..."
                }
                
                let mintResult = try await self.nftService.executeMint(
                    tag: tag,
                    session: session,
                    keyIndex: 0x01
                ) { progress in
                    Task { @MainActor in
                        session.alertMessage = progress
                    }
                }
                
                return mintResult
            }
        ) { result in
            switch result {
            case .success(let mintResult):
                completion(true, nil, mintResult.tokenId)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Mint failed"
                completion(false, errorMessage, nil)
            }
        }
    }
    
    /// Sign Message
    func signMessage(message: Data, completion: @escaping (Bool, UInt32?, UInt32?, String?, String?) -> Void) {
        performNFCOperation(
            operation: { tag, session -> (UInt32, UInt32, String) in
                await MainActor.run {
                    session.alertMessage = "Signing message..."
                }
                
                return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(UInt32, UInt32, String), Error>) in
                    let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, readerSession: session)
                    commandHandler.generateSignature(keyIndex: 0x01, messageDigest: message) { success, response, error, session in
                        
                        if success, let response = response, response.count >= 8 {
                            let globalCounterData = response.subdata(in: 0..<4)
                            let keyCounterData = response.subdata(in: 4..<8)
                            let derSignature = response.subdata(in: 8..<response.count)
                            
                            // Convert 4-byte Data to UInt32 (big-endian) with bounds checking
                            guard globalCounterData.count == 4, keyCounterData.count == 4 else {
                                continuation.resume(throwing: AppError.nfc(.chipError("Invalid counter data length")))
                                return
                            }
                            
                            let globalCounter = globalCounterData.withUnsafeBytes { buffer -> UInt32 in
                                guard buffer.count >= MemoryLayout<UInt32>.size else {
                                    return 0
                                }
                                return buffer.load(as: UInt32.self).bigEndian
                            }
                            let keyCounter = keyCounterData.withUnsafeBytes { buffer -> UInt32 in
                                guard buffer.count >= MemoryLayout<UInt32>.size else {
                                    return 0
                                }
                                return buffer.load(as: UInt32.self).bigEndian
                            }
                            let derSignatureHex = derSignature.hexEncodedString()
                            
                            continuation.resume(returning: (globalCounter, keyCounter, derSignatureHex))
                        } else {
                            let errorMsg = error ?? "Failed to generate signature"
                            continuation.resume(throwing: AppError.nfc(.chipError(errorMsg)))
                        }
                    }
                }
            }
        ) { result in
            switch result {
            case .success(let (globalCounter, keyCounter, derSignatureHex)):
                completion(true, globalCounter, keyCounter, derSignatureHex, nil)
            case .failure(let error):
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to generate signature"
                completion(false, nil, nil, nil, errorMessage)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getTokenIdForChip(contractId: String, publicKey: Data) async throws -> UInt64 {
        guard let wallet = walletService.getStoredWallet() else {
            throw AppError.wallet(.noWallet)
        }
        
        // Use public address only - no private key needed for read-only queries
        return try await blockchainService.getTokenId(
            contractId: contractId,
            publicKey: publicKey,
            accountId: wallet.address
        )
    }
}
