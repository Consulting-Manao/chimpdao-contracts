import SwiftUI

struct WalletAddressCard: View {
    let address: String
    let network: AppNetwork
    @State private var copied = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallet Address")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(address)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
            
            HStack(spacing: 12) {
                Button(action: copyAddress) {
                    Label("Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(copied ? .green : .chimpYellow)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: openStellarExpert) {
                    Label("View on Stellar.Expert", systemImage: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.chimpYellow)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private func copyAddress() {
        UIPasteboard.general.string = address
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
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

