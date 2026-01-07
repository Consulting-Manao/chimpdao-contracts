import SwiftUI
import UIKit

struct WalletAddressCard: View {
    let address: String
    let network: AppNetwork
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallet Address")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(address)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
            
            HStack(spacing: 12) {
                CopyButton(address)
                
                Button(action: openStellarExpert) {
                    Label("View on Stellar.Expert", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.chimpYellow)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private func openStellarExpert() {
        let baseUrl: String
        switch network {
        case .testnet:
            baseUrl = "https://stellar.expert/explorer/testnet/account"
        case .mainnet:
            baseUrl = "https://stellar.expert/explorer/public/account"
        }
        
        let urlString = "\(baseUrl)/\(address)"
        guard let url = URL(string: urlString) else { return }
        
        openURL(url)
    }
}

