import SwiftUI

struct ScannedItemView: View {
    let item: ScannedItem
    let onDismiss: () -> Void
    @EnvironmentObject var appData: AppData
    @State private var ownerAddress: String?
    @State private var isLoading = true
    @State private var isUnclaimed = false
    @State private var showClaimView = false
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Close", action: onDismiss)
                Spacer()
            }
            .padding()
            
            Text("Scanned Item")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 15) {
                    if let tokenId = item.tokenId {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Token ID:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(tokenId)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contract ID:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(item.contractId)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if let owner = ownerAddress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Owner:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(owner)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    } else if isUnclaimed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Status:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Unclaimed")
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if appData.isWalletConnected {
                        if isUnclaimed {
                            // Show Claim button for unclaimed tokens
                            Button(action: {
                                showClaimView = true
                            }) {
                                HStack {
                                    Image(systemName: "hand.raised.fill")
                                    Text("Claim")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)
                            .sheet(isPresented: $showClaimView) {
                                if let tokenIdStr = item.tokenId, let tokenIdNum = UInt64(tokenIdStr) {
                                    ClaimView(
                                        tokenId: tokenIdNum,
                                        contractId: item.contractId,
                                        onDismiss: {
                                            showClaimView = false
                                            // Reload item details after claiming
                                            Task {
                                                await loadItemDetails()
                                            }
                                        }
                                    )
                                    .environmentObject(appData)
                                }
                            }
                        } else if ownerAddress != nil {
                            // Show Transfer button only if token is claimed and user might be owner
                            // Note: In a full implementation, you'd check if current user is the owner
                        Button(action: {
                            // Navigate to transfer
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.arrow.left")
                                Text("Transfer")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        }
                    } else {
                        if isUnclaimed {
                            Text("Connect wallet to claim this token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                    } else {
                        Text("Connect wallet to transfer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
        }
        .task {
            await loadItemDetails()
        }
    }
    
    private func loadItemDetails() async {
        isLoading = true
        defer { isLoading = false }
        
        // Try to fetch owner from contract
        // If owner_of panics (token doesn't exist or is unclaimed), we'll catch it
        guard let tokenIdStr = item.tokenId,
              let tokenIdNum = UInt64(tokenIdStr) else {
            isUnclaimed = false
            ownerAddress = nil
            return
        }
        
        do {
            // Try to get owner - if this succeeds, token is claimed
            let owner = try await appData.blockchainService.getOwnerOf(
                contractId: item.contractId,
                tokenId: tokenIdNum
            )
            ownerAddress = owner
            isUnclaimed = false
        } catch {
            // If owner_of fails, token is either unclaimed or doesn't exist
            // For now, we'll assume it's unclaimed if the call fails
        ownerAddress = nil
            isUnclaimed = true
        }
    }
}
