import SwiftUI

struct TransferView: View {
    let onDismiss: () -> Void
    @EnvironmentObject var appData: AppData
    @State private var recipientAddress = ""
    @State private var tokenId = ""
    @State private var isTransferring = false
    @State private var currentStep: TransferStep = .idle
    @State private var result: TransferResult?
    
    enum TransferStep {
        case idle
        case reading
        case signing
        case recovering
        case calling
        case confirming
    }
    
    struct TransferResult {
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
            
            Text("Transfer NFT")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("From:")
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
                    Text("Recipient Address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter recipient Stellar address", text: $recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disabled(isTransferring)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Token ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter token ID", text: $tokenId)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .disabled(isTransferring)
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
                            await handleTransfer()
                        }
                    }) {
                        HStack {
                            if isTransferring {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isTransferring ? stepMessage : "Transfer NFT")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canTransfer ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!canTransfer || isTransferring)
                    
                    if isTransferring && currentStep != .idle {
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
    
    private var canTransfer: Bool {
        !recipientAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !tokenId.trimmingCharacters(in: .whitespaces).isEmpty &&
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
    
    private func handleTransfer() async {
        guard let wallet = appData.walletConnection else {
            result = TransferResult(success: false, message: "No wallet connected")
            return
        }
        
        guard let tokenIdNum = UInt64(tokenId.trimmingCharacters(in: .whitespaces)) else {
            result = TransferResult(success: false, message: "Invalid token ID")
            return
        }
        
        let recipient = recipientAddress.trimmingCharacters(in: .whitespaces)
        guard !recipient.isEmpty else {
            result = TransferResult(success: false, message: "Recipient address required")
            return
        }
        
        isTransferring = true
        currentStep = .idle
        result = nil
        
        do {
            let transferFunction = TransferFunction()
            let context = FunctionContext(
                contractId: NFCConfig.contractId,
                walletConnection: wallet,
                networkPassphrase: NFCConfig.networkPassphrase,
                rpcUrl: NFCConfig.rpcUrl,
                horizonUrl: NFCConfig.horizonUrl,
                chipAuthData: nil
            )
            
            let request = TransferRequest(
                from: wallet.address,
                to: recipient,
                tokenId: tokenIdNum,
                contractId: NFCConfig.contractId
            )
            
            currentStep = .reading
            let functionResult = try await transferFunction.executeTransfer(
                request: request,
                context: context,
                nfcService: appData.nfcService,
                blockchainService: appData.blockchainService,
                walletService: appData.walletService,
                stepCallback: { step in
                    currentStep = step
                }
            )
            
            result = TransferResult(
                success: functionResult.success,
                message: functionResult.message
            )
        } catch {
            result = TransferResult(
                success: false,
                message: error.localizedDescription
            )
        }
        
        isTransferring = false
        currentStep = .idle
    }
}
