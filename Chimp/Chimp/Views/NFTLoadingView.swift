import SwiftUI

struct NFTLoadingView: View {
    let contractId: String
    let tokenId: UInt64
    @Binding var isPresented: Bool
    @State private var metadata: NFTMetadata?
    @State private var imageData: Data?
    @State private var ownerAddress: String?
    @State private var isClaimed: Bool = true
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    private let blockchainService = BlockchainService()
    private let ipfsService = IPFSService()
    private let walletService = WalletService.shared
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .chimpYellow))
                    Text("Loading NFT...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .accessibilityLabel("Loading NFT")
            } else if let error = errorMessage {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                        .accessibilityHidden(true)
                    
                    Text("Error")
                        .font(.title2)
                        .fontWeight(.bold)
                        .accessibilityAddTraits(.isHeader)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilityLabel("Error: \(error)")
                    
                    Button("Close") {
                        isPresented = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if let metadata = metadata {
                NFTViewSwiftUI(
                    metadata: metadata,
                    imageData: imageData,
                    ownerAddress: ownerAddress,
                    isClaimed: isClaimed,
                    contractId: contractId,
                    tokenId: tokenId
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
        .onAppear {
            loadNFT()
        }
    }
    
    private func loadNFT() {
        Task {
            do {
                guard let wallet = walletService.getStoredWallet() else {
                    await MainActor.run {
                        errorMessage = "No wallet found"
                        isLoading = false
                    }
                    return
                }
                
                // Use public address only - no private key needed for read-only queries
                let accountId = wallet.address
                
                // Try to get the owner - if this succeeds, the NFT is claimed
                do {
                    let owner = try await blockchainService.getTokenOwner(
                        contractId: contractId,
                        tokenId: tokenId,
                        accountId: accountId
                    )
                    await MainActor.run {
                        ownerAddress = owner
                        isClaimed = true
                    }
                } catch let appError as AppError {
                    if case .blockchain(.contract(.tokenNotClaimed)) = appError {
                        await MainActor.run {
                            isClaimed = false
                        }
                    } else {
                        throw appError
                    }
                }
                
                // Get token URI
                let ipfsUrl = try await blockchainService.getTokenUri(
                    contractId: contractId,
                    tokenId: tokenId,
                    accountId: accountId
                )
                
                // Convert IPFS URL to HTTP gateway URL
                let httpMetadataUrl = ipfsService.convertToHTTPGateway(ipfsUrl)
                
                // Download NFT metadata from IPFS
                let downloadedMetadata = try await ipfsService.downloadNFTMetadata(from: httpMetadataUrl)
                
                // Download image if available
                var downloadedImageData: Data? = nil
                if let imageUrl = downloadedMetadata.image {
                    let httpImageUrl = ipfsService.convertToHTTPGateway(imageUrl)
                    downloadedImageData = try await ipfsService.downloadImageData(from: httpImageUrl)
                }
                
                await MainActor.run {
                    metadata = downloadedMetadata
                    imageData = downloadedImageData
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? AppError)?.localizedDescription ?? "Failed to load NFT information."
                    isLoading = false
                }
            }
        }
    }
}

