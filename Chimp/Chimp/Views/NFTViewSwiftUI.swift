import SwiftUI
import UIKit

struct NFTViewSwiftUI: View {
    let metadata: NFTMetadata
    let imageData: Data?
    let ownerAddress: String?
    let isClaimed: Bool
    let contractId: String
    let tokenId: UInt64
    
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
        .navigationTitle("NFT Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: nftURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
    
    private var nftURL: URL {
        URL(string: "https://nft.chimpdao.xyz/\(contractId)/\(tokenId)")!
    }
    
    @ViewBuilder
    private var ownerStatusView: some View {
        if isClaimed {
            if let ownerAddress = ownerAddress {
                HStack {
                    Text("Owner:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(ownerAddress)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Owner: \(ownerAddress)")
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

