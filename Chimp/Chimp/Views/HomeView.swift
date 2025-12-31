import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle pattern
                Color.chimpBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header with logo
                        headerSection
                        
                        VStack(spacing: 20) {
                            // Error message
                            if let error = viewModel.errorMessage {
                                HStack(alignment: .center, spacing: 12) {
                                    Text(error)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Button(action: {
                                        viewModel.dismissError()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.1))
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                            
                            // Main action cards
                            actionCardsSection
                                .padding(.horizontal, 20)
                                .padding(.top, viewModel.errorMessage == nil ? 16 : 0)
                        }
                        .padding(.bottom, 32)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Empty toolbar to remove default title
                }
            }
            .overlay {
                // Confetti overlay for success animations
                if viewModel.showingConfetti {
                    ConfettiOverlay(message: viewModel.confettiMessage ?? "")
                }
            }
            .sheet(isPresented: $viewModel.showingNFTView) {
                if let contractId = viewModel.loadedNFTContractId,
                   let tokenId = viewModel.loadedNFTTokenId {
                    NavigationView {
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
                TransferInputView(isPresented: $viewModel.showingTransferAlert) { recipient, tokenId in
                    viewModel.transferNFT(recipient: recipient, tokenId: tokenId)
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
                .padding(.top, 24)
                .padding(.bottom, 24)
        }
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            // Load NFT Card
            ActionCard(
                icon: "photo.fill",
                title: "Load NFT",
                description: "Scan an NFC chip to view its NFT",
                color: .blue,
                action: {
                    viewModel.loadNFT()
                }
            )
            
            // Claim NFT Card
            ActionCard(
                icon: "hand.raised.fill",
                title: "Claim NFT",
                description: "Claim ownership of an unclaimed NFT",
                color: .purple,
                action: {
                    viewModel.claimNFT()
                }
            )
            
            // Transfer NFT Card
            ActionCard(
                icon: "arrow.right.circle.fill",
                title: "Transfer NFT",
                description: "Transfer an NFT to another address",
                color: .orange,
                action: {
                    viewModel.transferNFT()
                }
            )
            
            // Sign Message Card
            ActionCard(
                icon: "signature",
                title: "Sign Message",
                description: "Sign a message with your NFC chip",
                color: .green,
                action: {
                    viewModel.signMessage()
                }
            )
            
            // Mint NFT Card (Admin only)
            if AppConfig.shared.isAdminMode {
                ActionCard(
                    icon: "sparkles",
                    title: "Mint NFT",
                    description: "Initialize and mint a new NFT",
                    color: .indigo,
                    action: {
                        viewModel.mintNFT()
                    }
                )
            }
        }
    }
}

