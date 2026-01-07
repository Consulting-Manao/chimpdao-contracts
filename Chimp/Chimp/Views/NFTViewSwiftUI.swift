import SwiftUI
import UIKit

struct NFTViewSwiftUI: View {
    let metadata: NFTMetadata
    let imageData: Data?
    let ownerAddress: String?
    let isClaimed: Bool
    let contractId: String
    let tokenId: UInt64
    
    @State private var showingShareOptions = false
    @Environment(\.openURL) private var openURL
    
    private let walletService = WalletService.shared
    
    private var isOwnedByCurrentUser: Bool {
        guard let ownerAddress = ownerAddress,
              let currentWallet = walletService.getStoredWallet() else {
            return false
        }
        return ownerAddress == currentWallet.address
    }
    
    private var nftURL: URL {
        // Contract IDs are validated base32, so this should always succeed
        // Using URL components for safety
        var components = URLComponents()
        components.scheme = "https"
        components.host = "nft.chimpdao.xyz"
        components.path = "/\(contractId)/\(tokenId)"
        return components.url ?? URL(string: "https://nft.chimpdao.xyz")!
    }
    
    private var shareMessage: String {
        let name = metadata.name ?? "my collectible"
        return "Check out \(name) on Stellar Merch Shop! \(nftURL.absoluteString)"
    }
    
    private var twitterShareURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "twitter.com"
        components.path = "/intent/tweet"
        components.queryItems = [URLQueryItem(name: "text", value: shareMessage)]
        return components.url ?? URL(string: "https://twitter.com")!
    }
    
    private var telegramShareURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "t.me"
        components.path = "/share/url"
        components.queryItems = [
            URLQueryItem(name: "url", value: nftURL.absoluteString),
            URLQueryItem(name: "text", value: shareMessage)
        ]
        return components.url ?? URL(string: "https://t.me")!
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // NFT Image
                Group {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 100))
                            .foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: 300, maxHeight: 300)
                .cornerRadius(12)
                .background(Color(.systemGray6))
                .padding(.top, 20)
                .accessibilityLabel("NFT image")
                
                // Name
                Text(metadata.name ?? "Unnamed NFT")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                
                // Description
                Text(metadata.description ?? "No description available")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Owner Status
                ownerStatusView
                    .padding(.horizontal, 20)
                
                // Attributes
                if let attributes = metadata.attributes, !attributes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attributes")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .accessibilityAddTraits(.isHeader)
                        
                        ForEach(attributes.indices, id: \.self) { index in
                            AttributeRow(attribute: attributes[index])
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                }
                
                Spacer(minLength: 20)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingShareOptions = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog("Share", isPresented: $showingShareOptions, titleVisibility: .hidden) {
            Button {
                openURL(twitterShareURL)
            } label: {
                Label("Share on X", systemImage: "xmark")
            }
            
            Button {
                openURL(telegramShareURL)
            } label: {
                Label("Share on Telegram", systemImage: "paperplane.fill")
            }
            
            ShareLink(item: nftURL, message: Text(shareMessage)) {
                Label("More Options", systemImage: "ellipsis")
            }
            
            Button("Cancel", role: .cancel) {}
        }
    }
    
    @ViewBuilder
    private var ownerStatusView: some View {
        if isClaimed {
            if let ownerAddress = ownerAddress {
                if isOwnedByCurrentUser {
                    // Special styling for NFTs owned by current user
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundColor(.green)
                            Text("You own this NFT")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        
                        Text(ownerAddress)
                            .font(.custom("SFMono-Regular", size: 11))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .accessibilityLabel("You own this NFT. Address: \(ownerAddress)")
                } else {
                    // Different owner
                    HStack {
                        Text("Owner:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(ownerAddress)
                            .font(.custom("SFMono-Regular", size: 14))
                            .foregroundColor(.blue)
                            .textSelection(.enabled)
                    }
                    .accessibilityLabel("Owner: \(ownerAddress)")
                }
            } else {
                HStack {
                    Text("Owner:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Unknown")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .accessibilityLabel("Owner: Unknown")
            }
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("This token exists but has not been claimed yet. Use the 'Claim NFT' feature to claim ownership.")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            .accessibilityLabel("Unclaimed token. Use Claim NFT feature to claim ownership.")
        }
    }
}

struct AttributeRow: View {
    let attribute: NFTAttribute
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attribute.trait_type)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(attribute.value)
                .font(.body)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attribute.trait_type): \(attribute.value)")
    }
}



