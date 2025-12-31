import SwiftUI
import Combine

class HomeViewModel: ObservableObject {
    private let walletService = WalletService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingTransferAlert = false
    @Published var showingSignAlert = false
    @Published var showingNFTView = false
    @Published var loadedNFTContractId: String?
    @Published var loadedNFTTokenId: UInt64?
    
    // Result states for post-operation display
    @Published var showingSignatureView = false
    @Published var signatureData: (globalCounter: String, keyCounter: String, derSignature: String)?
    @Published var showingConfetti = false
    @Published var confettiMessage: String?
    
    // Operation coordinator will handle the actual NFC operations
    let nfcCoordinator = NFCOperationCoordinator()
    
    init() {
        setupCoordinatorCallbacks()
    }
    
    private func setupCoordinatorCallbacks() {
        nfcCoordinator.onLoadNFTSuccess = { [weak self] contractId, tokenId in
            DispatchQueue.main.async {
                self?.loadedNFTContractId = contractId
                self?.loadedNFTTokenId = tokenId
                self?.showingNFTView = true
            }
        }
        
        nfcCoordinator.onLoadNFTError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        nfcCoordinator.onClaimSuccess = { [weak self] tokenId in
            DispatchQueue.main.async {
                // Reset coordinator state first to ensure clean state
                self?.nfcCoordinator.resetState()
                // Show confetti briefly, then load NFT
                self?.showConfetti(message: "Claim successful!")
                // After confetti, load the NFT
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self?.loadedNFTContractId = AppConfig.shared.contractId
                    self?.loadedNFTTokenId = tokenId
                    self?.showingNFTView = true
                }
            }
        }
        
        nfcCoordinator.onClaimError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        nfcCoordinator.onTransferSuccess = { [weak self] in
            DispatchQueue.main.async {
                // NFC session already showed success message, no need for extra alert
                self?.nfcCoordinator.resetState()
            }
        }
        
        nfcCoordinator.onTransferError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        nfcCoordinator.onSignSuccess = { [weak self] globalCounter, keyCounter, signature in
            DispatchQueue.main.async {
                self?.signatureData = (globalCounter, keyCounter, signature)
                self?.showingSignatureView = true
            }
        }
        
        nfcCoordinator.onSignError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
        
        nfcCoordinator.onMintSuccess = { [weak self] tokenId in
            DispatchQueue.main.async {
                // Reset coordinator state first to ensure clean state
                self?.nfcCoordinator.resetState()
                // Show confetti briefly - no need for extra alert since NFC session already showed success
                self?.showConfetti(message: "Mint successful! Token ID: \(tokenId)")
            }
        }
        
        nfcCoordinator.onMintError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error
            }
        }
    }
    
    private func showConfetti(message: String) {
        confettiMessage = message
        showingConfetti = true
        // Hide confetti after 3 seconds - no need for extra alert since NFC session already provided feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.showingConfetti = false
        }
    }
    
    func loadNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        // Reset coordinator state first to ensure clean state
        nfcCoordinator.resetState()
        
        isLoading = true
        errorMessage = nil
        
        nfcCoordinator.loadNFT { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error
                }
            }
        }
    }
    
    func claimNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        errorMessage = nil
        // Start NFC operation immediately - no modal
        nfcCoordinator.claimNFT { success, error in
            // Results handled via callbacks
        }
    }
    
    func transferNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        showingTransferAlert = true
    }
    
    func transferNFT(recipient: String, tokenId: UInt64) {
        errorMessage = nil
        // Start NFC operation immediately - no modal
        nfcCoordinator.transferNFT(recipientAddress: recipient, tokenId: tokenId) { success, error in
            // Results handled via callbacks
        }
    }
    
    func signMessage() {
        showingSignAlert = true
    }
    
    func signMessage(message: Data) {
        errorMessage = nil
        // Start NFC operation immediately - no modal
        nfcCoordinator.signMessage(message: message) { success, globalCounter, keyCounter, signature in
            // Results handled via callbacks
        }
    }
    
    func mintNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        guard !AppConfig.shared.contractId.isEmpty else {
            errorMessage = "Please set the contract ID in Settings"
            return
        }
        
        guard AppConfig.shared.isAdminMode else {
            errorMessage = "Admin mode required for minting"
            return
        }
        
        errorMessage = nil
        // Start NFC operation immediately - no modal
        nfcCoordinator.mintNFT { success, error in
            // Results handled via callbacks
        }
    }
}

