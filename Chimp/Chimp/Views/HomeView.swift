import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var appConfig = AppConfig.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with logo
                    headerSection
                    
                    VStack(spacing: 16) {
                        // Error message
                        if let error = viewModel.errorMessage {
                            ErrorBanner(
                                error: error,
                                onDismiss: {
                                    viewModel.dismissError()
                                },
                                onRetry: nil,
                                onCheckSettings: (error.lowercased().contains("contract") || error.lowercased().contains("settings")) ? {
                                    viewModel.dismissError()
                                } : nil
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Main action cards
                        actionCardsSection
                            .padding(.horizontal, 20)
                            .padding(.top, viewModel.errorMessage == nil ? 16 : 0)
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.errorMessage)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.chimpBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                // Confetti overlay for success animations
                if viewModel.showingConfetti {
                    ConfettiOverlay(message: viewModel.confettiMessage ?? "")
                        .transition(.opacity)
                        .zIndex(1000)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.showingConfetti)
            .sheet(isPresented: $viewModel.showingNFTView) {
                if let contractId = viewModel.loadedNFTContractId,
                   let tokenId = viewModel.loadedNFTTokenId {
                    NavigationStack {
                        NFTLoadingView(
                            contractId: contractId,
                            tokenId: tokenId,
                            isPresented: $viewModel.showingNFTView
                        )
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Close") {
                                    viewModel.showingNFTView = false
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingTransferAlert) {
                if let tokenId = viewModel.transferTokenId {
                    TransferInputView(
                        isPresented: $viewModel.showingTransferAlert,
                        tokenId: tokenId
                    ) { recipient in
                        viewModel.executeTransfer(recipient: recipient)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSignAlert) {
                SignMessageInputView(isPresented: $viewModel.showingSignAlert) { message in
                    viewModel.signMessage(message: message)
                }
            }
            .sheet(isPresented: $viewModel.showingSignatureView) {
                if let signature = viewModel.signatureData {
                    SignatureDisplayView(
                        globalCounter: signature.globalCounter,
                        keyCounter: signature.keyCounter,
                        derSignature: signature.derSignature,
                        isPresented: $viewModel.showingSignatureView
                    )
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .accessibilityLabel("Chimp logo")
        }
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            // Claim NFT Card (reads contract ID from chip NDEF)
            ActionCard(
                icon: "hand.raised.fill",
                title: "Claim NFT",
                color: .purple,
                action: {
                    viewModel.claimNFT()
                }
            )
            
            // Load NFT Card
            ActionCard(
                icon: "photo.fill",
                title: "Load NFT",
                color: .blue,
                action: {
                    viewModel.loadNFT()
                }
            )
            
            // Transfer NFT Card (reads contract ID and token ID from chip NDEF)
            ActionCard(
                icon: "arrow.right.circle.fill",
                title: "Transfer NFT",
                color: .orange,
                action: {
                    viewModel.transferNFT()
                }
            )
            
            // Sign Message Card (Admin only)
            if appConfig.isAdminMode {
                ActionCard(
                    icon: "signature",
                    title: "Sign Message",
                    color: .green,
                    action: {
                        viewModel.signMessage()
                    }
                )
            }
            
            // Mint NFT Card (Admin only, requires contract ID)
            if appConfig.isAdminMode && !appConfig.contractId.isEmpty {
                ActionCard(
                    icon: "sparkles",
                    title: "Mint NFT",
                    color: .indigo,
                    action: {
                        viewModel.mintNFT()
                    }
                )
            }
        }
    }
}

