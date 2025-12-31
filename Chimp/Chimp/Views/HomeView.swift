import SwiftUI

// Preference key to track scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle pattern
                Color.chimpBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header with scroll-based zoom
                        headerSection(scrollOffset: scrollOffset)
                            .id("header")
                            .background(
                                GeometryReader { headerGeometry in
                                    let offset = headerGeometry.frame(in: .named("scroll")).minY
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetPreferenceKey.self,
                                            value: max(0, -offset)
                                        )
                                }
                            )
                        
                        VStack(spacing: 20) {
                            // Error message
                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .coordinateSpace(name: "scroll")
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .onAppear {
                    scrollOffset = 0
                }
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
    
    @ViewBuilder
    private func headerSection(scrollOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Calculate scale based on scroll offset
            // Logo starts at scale 1.0 when at top (scrollOffset = 0)
            // Scales down to 0.7 as user scrolls down
            let minScale: CGFloat = 0.7
            let maxScroll: CGFloat = 100 // Full scale transition over 100pt
            let scrollProgress = min(scrollOffset / maxScroll, 1.0)
            let scale = 1.0 - (scrollProgress * (1.0 - minScale))
            let finalScale = max(minScale, scale)
            
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .scaleEffect(finalScale)
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

