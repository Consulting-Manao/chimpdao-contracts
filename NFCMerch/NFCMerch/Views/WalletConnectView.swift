/**
 * Wallet Connect View
 * UI for connecting external wallets or entering manual secret key/mnemonic
 */

import SwiftUI

struct WalletConnectView: View {
    @EnvironmentObject var appData: AppData
    @State private var selectedTab = 0  // 0 = external, 1 = manual
    @State private var manualKeyType = 0  // 0 = secret key, 1 = mnemonic
    @State private var secretKey = ""
    @State private var mnemonic = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    var body: some View {
        if appData.isWalletConnected {
            connectedWalletView
        } else {
        VStack(spacing: 20) {
            Text("Connect Wallet")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Connect an external wallet or enter your secret key/mnemonic")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Picker("Wallet Type", selection: $selectedTab) {
                Text("External").tag(0)
                Text("Manual").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            if selectedTab == 0 {
                externalWalletView
            } else {
                manualWalletView
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .padding()
        }
    }
    
    @ViewBuilder
    private var connectedWalletView: some View {
        VStack(spacing: 15) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Wallet Connected")
                .font(.headline)
            
            if let wallet = appData.walletConnection {
                VStack(spacing: 8) {
                    Text("Address:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(wallet.address)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .textSelection(.enabled)
                }
                .padding()
            }
            
            Button("Disconnect") {
                appData.walletConnection = nil
                // Clear stored wallet
                UserDefaults.standard.removeObject(forKey: "wallet_type")
                UserDefaults.standard.removeObject(forKey: "wallet_address")
            }
            .buttonStyle(.bordered)
            .foregroundColor(.red)
        }
        .padding()
    }
    
    private var externalWalletView: some View {
        VStack(spacing: 15) {
            Text("Connect External Wallet")
                .font(.headline)
            
            Text("Choose a wallet app to connect:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Wallet options (will be populated from stellar-swift-wallet-sdk when implemented)
            Button("Freighter") {
                Task {
                    await connectExternalWallet("Freighter")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isConnecting)
            
            Button("LOBSTR") {
                Task {
                    await connectExternalWallet("LOBSTR")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isConnecting)
            
            if isConnecting {
                ProgressView()
            }
        }
    }
    
    private var manualWalletView: some View {
        VStack(spacing: 15) {
            Text("Enter Secret Key or Mnemonic")
                .font(.headline)
            
            Picker("Key Type", selection: $manualKeyType) {
                Text("Secret Key").tag(0)
                Text("Mnemonic").tag(1)
            }
            .pickerStyle(.segmented)
            
            if manualKeyType == 0 {
                SecureField("Secret Key (S...)", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                
                Button("Connect") {
                    Task {
                        await connectManualSecretKey()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(secretKey.isEmpty || isConnecting)
            } else {
                TextField("Mnemonic (12 or 24 words)", text: $mnemonic, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                
                Button("Connect") {
                    Task {
                        await connectManualMnemonic()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(mnemonic.isEmpty || isConnecting)
            }
            
            if isConnecting {
                ProgressView()
            }
        }
        .padding(.horizontal)
    }
    
    private func connectExternalWallet(_ walletName: String) async {
        isConnecting = true
        errorMessage = nil
        
        do {
            let connection = try await appData.walletService.connectExternalWallet(walletType: walletName)
            appData.walletConnection = connection
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isConnecting = false
    }
    
    private func connectManualSecretKey() async {
        isConnecting = true
        errorMessage = nil
        
        do {
            let connection = try await appData.walletService.loadWalletFromSecretKey(secretKey)
            appData.walletConnection = connection
            secretKey = "" // Clear for security
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isConnecting = false
    }
    
    private func connectManualMnemonic() async {
        isConnecting = true
        errorMessage = nil
        
        do {
            let connection = try await appData.walletService.loadWalletFromMnemonic(mnemonic)
            appData.walletConnection = connection
            mnemonic = "" // Clear for security
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isConnecting = false
    }
}

