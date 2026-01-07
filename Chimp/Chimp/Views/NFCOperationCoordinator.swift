import Foundation
import UIKit
import CoreNFC
import stellarsdk
import OSLog

/// Coordinator to bridge SwiftUI to existing UIKit NFC functionality
class NFCOperationCoordinator: NSObject {
    private let walletService = WalletService.shared
    private let claimService = ClaimService()
    private let transferService = TransferService()
    private let mintService = MintService()
    private let blockchainService = BlockchainService()
    private let ipfsService = IPFSService()
    
    // MARK: - Constants
    
    // Callbacks
    var onLoadNFTSuccess: ((String, UInt64) -> Void)?
    var onLoadNFTError: ((String) -> Void)?
    var onClaimSuccess: ((UInt64) -> Void)? // tokenId
    var onClaimError: ((String) -> Void)?
    var onTransferSuccess: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    var onSignSuccess: ((UInt32, UInt32, String) -> Void)? // globalCounter, keyCounter, signature
    var onSignError: ((String) -> Void)?
    var onMintSuccess: ((UInt64) -> Void)? // tokenId
    var onMintError: ((String) -> Void)?
    
    // Helper to get ViewController for presenting
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return nil
        }
        return rootViewController
    }
    
    // MARK: - Load NFT
    func loadNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Hold your iPhone near the chip to view NFT"
        session?.begin()
        
        // Store completion for later
        loadNFTCompletion = completion
    }
    
    private var loadNFTCompletion: ((Bool, String?) -> Void)?
    
    // Store NFCHelper instances to prevent deallocation
    private var claimNFCHelper: NFCHelper?
    private var transferNFCHelper: NFCHelper?
    private var transferReadNFCHelper: NFCHelper?
    private var mintNFCHelper: NFCHelper?
    
    // MARK: - Claim NFT
    func claimNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        // Contract ID is read from chip NDEF, not from Settings
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        claimNFCHelper = NFCHelper()
        claimNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Preparing to claim NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let claimResult = try await self.claimService.executeClaim(
                            tag: tag,
                            session: session,
                            keyIndex: 0x01
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "NFT claimed successfully!"
                            session.invalidate()
                            completion(true, nil)
                            // Trigger callback with tokenId for NFT loading
                            self.onClaimSuccess?(claimResult.tokenId)
                            self.claimNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Claim failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onClaimError?(errorMessage)
                            self.claimNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onClaimError?(errorMsg)
                self.claimNFCHelper = nil
            }
        }
        claimNFCHelper?.BeginSession()
    }
    
    // MARK: - Read NFT for Transfer (first scan to get token ID)
    func readNFTForTransfer(completion: @escaping (Bool, UInt64?, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, nil, "Please login first")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, nil, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        transferReadNFCHelper = NFCHelper()
        transferReadNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                Task { @MainActor in
                    session.alertMessage = "Reading chip information..."
                }
                
                Task.detached {
                    do {
                        // Read NDEF to get contract ID and token ID
                        let ndefUrl = try await NDEFReader.readNDEFUrl(tag: tag, session: session)
                        guard let ndefUrl = ndefUrl else {
                            throw AppError.validation("No NDEF data found on chip")
                        }
                        
                        let tokenId = NDEFReader.parseTokenIdFromNDEFUrl(ndefUrl)
                        guard let tokenId = tokenId else {
                            throw AppError.validation("Token ID not found on chip. This NFT may not be claimed yet.")
                        }
                        
                        await MainActor.run {
                            session.alertMessage = "Chip read successfully!"
                            session.invalidate()
                            completion(true, tokenId, nil)
                            self.transferReadNFCHelper = nil
                        }
                    } catch let error as AppError {
                        await MainActor.run {
                            session.alertMessage = error.localizedDescription
                            session.invalidate(errorMessage: error.localizedDescription)
                            completion(false, nil, error.localizedDescription)
                            self.transferReadNFCHelper = nil
                        }
                    } catch {
                        let message = "Error reading chip: \(error.localizedDescription)"
                        await MainActor.run {
                            session.alertMessage = message
                            session.invalidate(errorMessage: message)
                            completion(false, nil, message)
                            self.transferReadNFCHelper = nil
                        }
                    }
                }
            } else if let error = error {
                completion(false, nil, error)
                self.transferReadNFCHelper = nil
            }
        }
        
        transferReadNFCHelper?.BeginSession()
    }
    
    // MARK: - Transfer NFT (second scan to complete transfer)
    func transferNFT(recipientAddress: String, tokenId: UInt64, completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        // Contract ID is read from chip NDEF, not from Settings
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        transferNFCHelper = NFCHelper()
        transferNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Preparing to transfer NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        _ = try await self.transferService.executeTransfer(
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
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "NFT transferred successfully!"
                            session.invalidate()
                            completion(true, nil)
                            self.onTransferSuccess?()
                            self.transferNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Transfer failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onTransferError?(errorMessage)
                            self.transferNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onTransferError?(errorMsg)
                self.transferNFCHelper = nil
            }
        }
        transferNFCHelper?.BeginSession()
    }
    
    // MARK: - Sign Message
    func signMessage(message: Data, completion: @escaping (Bool, UInt32?, UInt32?, String?) -> Void) {
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, nil, nil, "NFC is not available on this device")
            return
        }
        
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Hold your iPhone near the chip to sign message"
        session?.begin()
        
        // Store message and completion
        signMessageData = message
        signMessageCompletion = completion
    }
    
    private var signMessageData: Data?
    private var signMessageCompletion: ((Bool, UInt32?, UInt32?, String?) -> Void)?
    
    // MARK: - Mint NFT
    func mintNFT(completion: @escaping (Bool, String?) -> Void) {
        guard walletService.getStoredWallet() != nil else {
            completion(false, "Please login first")
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            completion(false, "Please set the contract ID in Settings")
            return
        }
        
        guard AppConfig.shared.isAdminMode else {
            completion(false, "Admin mode required for minting")
            return
        }
        
        guard NFCTagReaderSession.readingAvailable else {
            completion(false, "NFC is not available on this device")
            return
        }
        
        // Store helper as property to prevent deallocation
        mintNFCHelper = NFCHelper()
        mintNFCHelper?.OnTagEvent = { [weak self] success, tag, session, error in
            guard let self = self else { return }
            if success, let tag = tag, let session = session {
                // Show loading state immediately
                Task { @MainActor in
                    session.alertMessage = "Preparing to mint NFT..."
                }
                
                // Run blockchain operations on background thread
                Task.detached {
                    do {
                        let mintResult = try await self.mintService.executeMint(
                            tag: tag,
                            session: session,
                            keyIndex: 0x01
                        ) { progress in
                            Task { @MainActor in
                                session.alertMessage = progress
                            }
                        }
                        
                        // Success - update UI on main thread
                        await MainActor.run {
                            session.alertMessage = "NFT minted successfully!"
                            session.invalidate()
                            completion(true, nil)
                            // Trigger callback with tokenId
                            self.onMintSuccess?(mintResult.tokenId)
                            self.mintNFCHelper = nil
                        }
                    } catch {
                        // Error - update UI on main thread
                        await MainActor.run {
                            let errorMessage = (error as? AppError)?.localizedDescription ?? "Mint failed"
                            session.invalidate(errorMessage: errorMessage)
                            completion(false, errorMessage)
                            self.onMintError?(errorMessage)
                            self.mintNFCHelper = nil
                        }
                    }
                }
            } else {
                let errorMsg = error ?? "Failed to detect NFC tag"
                completion(false, errorMsg)
                self.onMintError?(errorMsg)
                self.mintNFCHelper = nil
            }
        }
        mintNFCHelper?.BeginSession()
    }
    
    /// Reset all NFC helper state - call this if operations get stuck
    func resetState() {
        claimNFCHelper = nil
        transferNFCHelper = nil
        mintNFCHelper = nil
        loadNFTCompletion = nil
        signMessageData = nil
        signMessageCompletion = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension NFCOperationCoordinator: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        Logger.logDebug("Session became active", category: .nfc)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Logger.logDebug("Session invalidated with error: \(error)", category: .nfc)
        
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                // User canceled, notify completion
                if let completion = loadNFTCompletion {
                    completion(false, "User canceled")
                    onLoadNFTError?("User canceled")
                    loadNFTCompletion = nil
                }
                if let completion = signMessageCompletion {
                    completion(false, nil, nil, "User canceled")
                    onSignError?("User canceled")
                    signMessageCompletion = nil
                    signMessageData = nil
                }
                return
            default:
                break
            }
        }
        
        // Handle other errors
        if let completion = loadNFTCompletion {
            let errorMsg = error.localizedDescription
            completion(false, errorMsg)
            onLoadNFTError?(errorMsg)
            loadNFTCompletion = nil
        }
        if let completion = signMessageCompletion {
            let errorMsg = error.localizedDescription
            completion(false, nil, nil, errorMsg)
            onSignError?(errorMsg)
            signMessageCompletion = nil
            signMessageData = nil
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        Logger.logDebug("Detected \(tags.count) tags", category: .nfc)
        
        guard let firstTag = tags.first else {
            session.invalidate(errorMessage: "No NFC tag found")
            return
        }
        
        // Handle load NFT
        if loadNFTCompletion != nil {
            Task {
                await handleLoadNFTTag(tag: firstTag, session: session)
            }
            return
        }
        
        // Handle sign message
        if signMessageCompletion != nil, let messageData = signMessageData {
            Task {
                await handleSignMessageTag(tag: firstTag, session: session, messageData: messageData)
            }
            return
        }
    }
    
    // MARK: - Load NFT Handler
    private func handleLoadNFTTag(tag: NFCTag, session: NFCTagReaderSession) async {
        guard case .iso7816(let iso7816Tag) = tag else {
            await MainActor.run {
                let errorMsg = "Invalid tag type"
                session.invalidate(errorMessage: errorMsg)
                loadNFTCompletion?(false, errorMsg)
                onLoadNFTError?(errorMsg)
                loadNFTCompletion = nil
            }
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                Logger.logError("Failed to connect to tag: \(error)", category: .nfc)
                session.invalidate(errorMessage: "Failed to connect to NFC tag")
            }
        }
        
        do {
            // Read NDEF to get contract ID
            let ndefUrl = try await NDEFReader.readNDEFUrl(tag: iso7816Tag, session: session)
            guard let ndefUrl = ndefUrl else {
                throw AppError.nfc(.readWriteFailed("No NDEF URL found"))
            }
            
            guard let contractId = NDEFReader.parseContractIdFromNDEFUrl(ndefUrl) else {
                throw AppError.validation("Invalid contract ID in NFC tag")
            }
            
            // Read chip public key
            let chipPublicKey = try await readChipPublicKey(tag: iso7816Tag, session: session, keyIndex: 0x01)
            guard let publicKeyData = Data(hexString: chipPublicKey) else {
                throw AppError.crypto(.invalidKey("Invalid public key format from chip"))
            }
            
            // Update session message before blockchain operation
            await MainActor.run {
                session.alertMessage = "Reading chip information..."
            }
            
            // Get token ID (this needs to happen while session is active for proper flow)
            let tokenId = try await getTokenIdForChip(contractId: contractId, publicKey: publicKeyData)
            
            // Close NFC session immediately after getting token ID
            await MainActor.run {
                session.alertMessage = "Chip information read successfully"
                session.invalidate()
            }
            
            // Continue on background thread to load NFT
            await MainActor.run {
                loadNFTCompletion?(true, nil)
                loadNFTCompletion = nil
                // Trigger NFT view presentation
                onLoadNFTSuccess?(contractId, tokenId)
            }
        } catch {
            await MainActor.run {
                let errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT"
                session.invalidate(errorMessage: errorMessage)
                loadNFTCompletion?(false, errorMessage)
                onLoadNFTError?(errorMessage)
                loadNFTCompletion = nil
            }
        }
    }
    
    // MARK: - Sign Message Handler
    private func handleSignMessageTag(tag: NFCTag, session: NFCTagReaderSession, messageData: Data) async {
        guard case .iso7816(let iso7816Tag) = tag else {
            await MainActor.run {
                session.invalidate(errorMessage: "Invalid tag type")
                signMessageCompletion?(false, nil, nil, "Invalid tag type")
                signMessageCompletion = nil
            }
            return
        }
        
        session.connect(to: tag) { error in
            if let error = error {
                Logger.logError("Failed to connect to tag: \(error)", category: .nfc)
                session.invalidate(errorMessage: "Failed to connect to NFC tag")
            }
        }
        
        let commandHandler = BlockchainCommandHandler(tag_iso7816: iso7816Tag, reader_session: session)
        commandHandler.ActionGenerateSignature(key_index: 0x01, message_digest: messageData) { [weak self] success, response, error, session in
            guard let self = self else { return }
            
            if success, let response = response, response.count >= 8 {
                guard response.count >= 8 else {
                    DispatchQueue.main.async {
                        let errorMsg = "Invalid response length: expected at least 8 bytes, got \(response.count)"
                        session.invalidate(errorMessage: errorMsg)
                        self.signMessageCompletion?(false, nil, nil, errorMsg)
                        self.onSignError?(errorMsg)
                        self.signMessageCompletion = nil
                        self.signMessageData = nil
                    }
                    return
                }
                
                let globalCounterData = response.subdata(in: 0..<4)
                let keyCounterData = response.subdata(in: 4..<8)
                let derSignature = response.subdata(in: 8..<response.count)
                
                // Convert 4-byte Data to UInt32 (big-endian) with bounds checking
                guard globalCounterData.count == 4, keyCounterData.count == 4 else {
                    DispatchQueue.main.async {
                        let errorMsg = "Invalid counter data length"
                        session.invalidate(errorMessage: errorMsg)
                        self.signMessageCompletion?(false, nil, nil, errorMsg)
                        self.onSignError?(errorMsg)
                        self.signMessageCompletion = nil
                        self.signMessageData = nil
                    }
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
                
                DispatchQueue.main.async {
                    session.alertMessage = "Message signed successfully"
                    session.invalidate()
                    self.signMessageCompletion?(true, globalCounter, keyCounter, derSignatureHex)
                    // Trigger callback
                    self.onSignSuccess?(globalCounter, keyCounter, derSignatureHex)
                    self.signMessageCompletion = nil
                    self.signMessageData = nil
                }
            } else {
                DispatchQueue.main.async {
                    let errorMsg = error ?? "Failed to generate signature"
                    session.invalidate(errorMessage: errorMsg)
                    self.signMessageCompletion?(false, nil, nil, errorMsg)
                    self.onSignError?(errorMsg)
                    self.signMessageCompletion = nil
                    self.signMessageData = nil
                }
            }
        }
    }
    
    private func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8) async throws -> String {
        return try await ChipOperations.readChipPublicKey(tag: tag, session: session, keyIndex: keyIndex)
    }
    
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

