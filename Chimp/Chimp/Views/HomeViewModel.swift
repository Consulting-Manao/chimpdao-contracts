import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    private let walletService = WalletService.shared
    
    @Published var isLoading = false
    @Published var errorMessage: String? {
        didSet {
            // Cancel existing timer when error message changes
            errorTimeoutTimer?.invalidate()
            errorTimeoutTimer = nil
            
            // Start new timer if error message is set
            if errorMessage != nil {
                startErrorTimeout()
            }
        }
    }
    @Published var showingTransferAlert = false
    @Published var transferTokenId: UInt64?
    @Published var transferRecipient: String?
    @Published var showingSignAlert = false
    @Published var showingNFTView = false
    @Published var loadedNFTContractId: String?
    @Published var loadedNFTTokenId: UInt64?
    
    // Result states for post-operation display
    @Published var showingSignatureView = false
    @Published var signatureData: (globalCounter: UInt32, keyCounter: UInt32, derSignature: String)?
    @Published var showingConfetti = false
    
    // IP Rights Acknowledgment state
    @Published var showingIPRightsAcknowledgment = false
    
    // Operation coordinator will handle the actual NFC operations
    let nfcCoordinator = NFCOperationCoordinator()
    
    // Timer for auto-dismissing error messages
    private var errorTimeoutTimer: Timer?
    
    init() {
        setupCoordinatorCallbacks()
    }
    
    deinit {
        errorTimeoutTimer?.invalidate()
    }
    
    private func setupCoordinatorCallbacks() {
        nfcCoordinator.onLoadNFTSuccess = { [weak self] contractId, tokenId in
            // self is @MainActor, so property access automatically hops to main actor
            self?.loadedNFTContractId = contractId
            self?.loadedNFTTokenId = tokenId
            self?.showingNFTView = true
        }
        
        nfcCoordinator.onLoadNFTError = { [weak self] error in
            self?.errorMessage = error
        }
        
        nfcCoordinator.onClaimSuccess = { [weak self] tokenId, contractId in
            // Show confetti briefly, then load NFT
            self?.showConfetti(message: "Claim successful!")
            // After confetti, load the NFT using contract ID from chip
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.loadedNFTContractId = contractId
                self?.loadedNFTTokenId = tokenId
                self?.showingNFTView = true
            }
        }
        
        nfcCoordinator.onClaimError = { [weak self] error in
            self?.errorMessage = error
        }
        
        nfcCoordinator.onTransferSuccess = { [weak self] in
            // Show confetti
            self?.showConfetti(message: "Transfer successful!")
        }
        
        nfcCoordinator.onTransferError = { [weak self] error in
            self?.errorMessage = error
        }
        
        nfcCoordinator.onSignSuccess = { [weak self] globalCounter, keyCounter, signature in
            self?.signatureData = (globalCounter: globalCounter, keyCounter: keyCounter, derSignature: signature)
            self?.showingSignatureView = true
        }
        
        nfcCoordinator.onSignError = { [weak self] error in
            self?.errorMessage = error
        }
        
        nfcCoordinator.onMintSuccess = { [weak self] tokenId in
            // Show confetti briefly - no need for extra alert since NFC session already showed success
            self?.showConfetti(message: "Mint successful! Token ID: \(tokenId)")
        }
        
        nfcCoordinator.onMintError = { [weak self] error in
            self?.errorMessage = error
        }
    }
    
    private func showConfetti(message: String = "") {
        showingConfetti = true
        // Hide confetti after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                self?.showingConfetti = false
            }
        }
    }
    
    func dismissError() {
        errorTimeoutTimer?.invalidate()
        errorTimeoutTimer = nil
        errorMessage = nil
    }
    
    
    private func startErrorTimeout() {
        // Cancel any existing timer
        errorTimeoutTimer?.invalidate()
        
        errorTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.errorMessage = nil
        }
    }
    
    func loadNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        nfcCoordinator.loadNFT { [weak self] success, error in
            self?.isLoading = false
            if let error = error {
                self?.errorMessage = error
            }
        }
    }
    
    func claimNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        // Check if user has acknowledged IP rights
        if !hasAcknowledgedIPRights() {
            // Show acknowledgment sheet first
            showingIPRightsAcknowledgment = true
            return
        }
        
        // User has already acknowledged, proceed with claim
        executeClaim()
    }
    
    func executeClaim() {
        // Contract ID is read from chip NDEF, not Settings
        errorMessage = nil
        nfcCoordinator.claimNFT { success, error in
        }
    }
    
    func acknowledgeIPRights() {
        UserDefaults.standard.set(true, forKey: "hasAcknowledgedIPRights")
        // After acknowledgment, execute the pending claim
        executeClaim()
    }
    
    private func hasAcknowledgedIPRights() -> Bool {
        return UserDefaults.standard.bool(forKey: "hasAcknowledgedIPRights")
    }
    
    func transferNFT() {
        guard walletService.getStoredWallet() != nil else {
            errorMessage = "Please login first"
            return
        }
        
        // Reset state
        transferTokenId = nil
        transferRecipient = nil
        errorMessage = nil
        
        // Start NFC scan to read token ID from chip
        nfcCoordinator.readNFTForTransfer { [weak self] success, tokenId, error in
            guard let self = self else { return }
            if success, let tokenId = tokenId {
                self.transferTokenId = tokenId
                self.showingTransferAlert = true
            } else if let error = error {
                self.errorMessage = error
            }
        }
    }
    
    func executeTransfer(recipient: String) {
        guard let tokenId = transferTokenId else {
            errorMessage = "Token ID not available"
            return
        }
        
        transferRecipient = recipient
        errorMessage = nil
        
        // Start NFC operation to complete transfer
        nfcCoordinator.transferNFT(recipientAddress: recipient, tokenId: tokenId) { success, error in
        }
    }
    
    func signMessage() {
        showingSignAlert = true
    }
    
    func signMessage(message: Data) {
        errorMessage = nil
        // Start NFC operation immediately - no modal
        nfcCoordinator.signMessage(message: message) { success, globalCounter, keyCounter, signature in
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
        }
    }
}

