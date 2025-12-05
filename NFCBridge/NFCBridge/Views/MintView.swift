/**
 * Mint View
 * Main UI for NFC-based NFT minting
 * Implements full mint flow: NFC → SEP-53 → signature → contract call
 */

import SwiftUI

struct MintView: View {
    @EnvironmentObject var appData: AppData
    @State private var isReadingChip = false
    @State private var currentStep: MintStep = .idle
    
    enum MintStep {
        case idle
        case readingChip
        case creatingMessage
        case signing
        case buildingTransaction
        case submitting
        case success
        case error(String)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button(action: {
                    appData.walletConnection = nil
                    UserDefaults.standard.removeObject(forKey: "wallet_type")
                    UserDefaults.standard.removeObject(forKey: "wallet_address")
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            Text("Mint NFT")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("Connected Wallet:")
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
            
            Text("Place your NFC chip on the back of your device to mint an NFT")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Status display
            switch currentStep {
            case .error(let message):
                Text("Error: \(message)")
                    .foregroundColor(.red)
                    .padding()
            case .success:
                if let tokenId = appData.lastMintedTokenId {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("NFT Minted Successfully!")
                            .font(.headline)
                        
                        Text("Token ID:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(tokenId)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            case .idle:
                // Show nothing for idle state
                EmptyView()
            default:
                ProgressView()
                    .scaleEffect(1.5)
                
                Text(stepMessage(currentStep))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Mint button
            Button(action: {
                Task {
                    await handleMint()
                }
            }) {
                Text(isIdle(currentStep) ? "Mint NFT" : "Minting...")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isIdle(currentStep) ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(!isIdle(currentStep))
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func isIdle(_ step: MintStep) -> Bool {
        if case .idle = step {
            return true
        }
        return false
    }
    
    private func stepMessage(_ step: MintStep) -> String {
        switch step {
        case .idle:
            return ""
        case .readingChip:
            return "Reading chip public key..."
        case .creatingMessage:
            return "Creating SEP-53 message..."
        case .signing:
            return "Waiting for chip signature..."
        case .buildingTransaction:
            return "Building transaction..."
        case .submitting:
            return "Submitting transaction..."
        case .success:
            return "Success!"
        case .error(let message):
            return message
        }
    }
    
    private func handleMint() async {
        guard let wallet = appData.walletConnection else {
            currentStep = .error("No wallet connected")
            return
        }
        
        appData.minting = true
        currentStep = .idle
        
        do {
            // 1. Read chip's public key
            // This will start NFC session and show iOS scan UI
            currentStep = .readingChip
            print("MintView: Starting to read chip - NFC scan UI should appear now")
            let chipPublicKey = try await readChipPublicKey()
            print("MintView: Chip public key read successfully")
            
            // 2. Fetch current ledger
            currentStep = .creatingMessage
            let currentLedger = try await appData.blockchainService.fetchCurrentLedger()
            let validUntilLedger = currentLedger + 100
            
            // 3. Create SEP-53 message
            let sep53Result = try createSEP53Message(
                contractId: NFCConfig.contractId,
                functionName: "mint",
                args: [wallet.address] as [Any],
                validUntilLedger: validUntilLedger,
                networkPassphrase: NFCConfig.networkPassphrase
            )
            
            // 4. Sign with chip (key index 1, recovery ID 1)
            currentStep = .signing
            let signature = try await signWithChip(messageHash: sep53Result.messageHash)
            
            // 5. Build transaction with signature from chip
            currentStep = .buildingTransaction
            let transaction = try await appData.blockchainService.buildMintTransaction(
                contractId: NFCConfig.contractId,
                to: wallet.address,
                message: sep53Result.message,
                signature: signature.signatureBytes,
                recoveryId: signature.recoveryId,
                sourceAccount: wallet.address
            )
            
            // 6. Sign transaction (external or local)
            let signedTx = try await signTransaction(transaction, wallet: wallet)
            
            // 7. Submit transaction
            currentStep = .submitting
            _ = try await appData.blockchainService.submitTransaction(signedTx)
            
            // Success!
            appData.lastMintedTokenId = chipPublicKey
            currentStep = .success
            
        } catch {
            currentStep = .error(error.localizedDescription)
            appData.mintError = error.localizedDescription
        }
        
        appData.minting = false
    }
    
    private func readChipPublicKey() async throws -> String {
        print("MintView: Starting to read chip public key...")
        return try await withCheckedThrowingContinuation { continuation in
            appData.nfcService.readPublicKey { result in
                switch result {
                case .success(let publicKey):
                    print("MintView: Successfully read public key: \(publicKey.prefix(20))...")
                    continuation.resume(returning: publicKey)
                case .failure(let error):
                    print("MintView: Error reading public key: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func signWithChip(messageHash: Data) async throws -> (signatureBytes: Data, recoveryId: UInt8) {
        return try await withCheckedThrowingContinuation { continuation in
            appData.nfcService.signMessage(messageHash: messageHash) { result in
                switch result {
                case .success(let (r, s, recoveryId)):
                    // Convert r and s hex strings to Data
                    let rBytes = hexToBytes(r)
                    let sBytes = hexToBytes(s)
                    
                    // Combine into 64-byte signature
                    var signatureBytes = Data()
                    signatureBytes.append(rBytes)
                    signatureBytes.append(sBytes)
                    
                    guard signatureBytes.count == 64 else {
                        continuation.resume(throwing: NSError(domain: "MintView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid signature length"]))
                        return
                    }
                    
                    continuation.resume(returning: (signatureBytes: signatureBytes, recoveryId: UInt8(recoveryId)))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func signTransaction(_ transaction: Data, wallet: WalletConnection) async throws -> Data {
        // Determine if external or local wallet based on connection type
        // For now, assume external wallet needs deep linking
        return try await appData.walletService.signTransactionExternal(transaction: transaction, wallet: wallet)
    }
}

