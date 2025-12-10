import SwiftUI

struct ClaimView: View {
    let tokenId: UInt64
    let contractId: String
    let onDismiss: () -> Void
    @EnvironmentObject var appData: AppData
    @State private var isClaiming = false
    @State private var currentStep: ClaimStep = .idle
    @State private var result: ClaimResult?
    
    enum ClaimStep {
        case idle
        case reading
        case signing
        case recovering
        case calling
        case confirming
    }
    
    struct ClaimResult {
        let success: Bool
        let message: String
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Back", action: onDismiss)
                Spacer()
            }
            .padding()
            
            Text("Claim NFT")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("Claimant:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
            }
            
            VStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Token ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(tokenId))
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                if let result = result {
                    if result.success {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)
                            Text(result.message)
                                .font(.headline)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text(result.message)
                                .font(.headline)
                                .foregroundColor(.red)
                        }
                        .padding()
                    }
                } else {
                    Button(action: {
                        Task {
                            await handleClaim()
                        }
                    }) {
                        HStack {
                            if isClaiming {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isClaiming ? stepMessage : "Claim NFT")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canClaim ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!canClaim || isClaiming)
                    
                    if isClaiming && currentStep != .idle {
                        Text(stepMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var canClaim: Bool {
        appData.isWalletConnected
    }
    
    private var stepMessage: String {
        switch currentStep {
        case .idle:
            return ""
        case .reading:
            return "Reading chip..."
        case .signing:
            return "Signing with chip..."
        case .recovering:
            return "Determining recovery ID..."
        case .calling:
            return "Calling contract..."
        case .confirming:
            return "Confirming transaction..."
        }
    }
    
    private func handleClaim() async {
        guard let wallet = appData.walletConnection else {
            result = ClaimResult(success: false, message: "No wallet connected")
            return
        }
        
        isClaiming = true
        currentStep = .idle
        result = nil
        
        do {
            let claimFunction = ClaimFunction()
            let context = FunctionContext(
                contractId: contractId,
                walletConnection: wallet,
                networkPassphrase: NFCConfig.networkPassphrase,
                rpcUrl: NFCConfig.rpcUrl,
                horizonUrl: NFCConfig.horizonUrl,
                chipAuthData: nil
            )
            
            currentStep = .reading
            let functionResult = try await claimFunction.executeClaim(
                contractId: contractId,
                tokenId: tokenId,
                context: context,
                nfcService: appData.nfcService,
                blockchainService: appData.blockchainService,
                walletService: appData.walletService,
                stepCallback: { step in
                    currentStep = step
                }
            )
            
            result = ClaimResult(
                success: functionResult.success,
                message: functionResult.message
            )
        } catch {
            result = ClaimResult(
                success: false,
                message: error.localizedDescription
            )
        }
        
        isClaiming = false
        currentStep = .idle
    }
}
