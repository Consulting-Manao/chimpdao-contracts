import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var walletState: WalletState
    @State private var contractId: String = AppConfig.shared.contractId
    @State private var originalContractId: String = ""
    @State private var showLogoutAlert = false
    @State private var showResetAlert = false
    @State private var contractCopied = false
    @State private var saveStatus: String?
    @Environment(\.openURL) private var openURL
    
    private let walletService = WalletService()
    private var currentNetwork: AppNetwork {
        AppConfig.shared.currentNetwork
    }
    
    // Check if contract ID has been modified from original
    private var hasChanges: Bool {
        contractId.trimmingCharacters(in: .whitespacesAndNewlines) != originalContractId.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Check if current value is at build config default
    private var isAtDefault: Bool {
        let buildConfigId = AppConfig.shared.getBuildConfigContractId()
        let currentId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentId == buildConfigId || (currentId.isEmpty && buildConfigId.isEmpty)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Wallet Address Section
                if let wallet = walletService.getStoredWallet() {
                    Section(header: Text("Wallet")) {
                        WalletAddressCard(
                            address: wallet.address,
                            network: currentNetwork
                        )
                    }
                }
                
                Section(header: Text("Smart Contract")) {
                    TextField("Enter contract address", text: $contractId)
                        .font(.system(size: 15, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if hasChanges {
                        Button(action: saveContractId) {
                            HStack {
                                if let status = saveStatus {
                                    Label(status, systemImage: "checkmark")
                                        .foregroundColor(.green)
                                } else {
                                    Text("Save")
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    if !contractId.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: copyContractId) {
                                Label("Copy", systemImage: contractCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(contractCopied ? .green : .chimpYellow)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: openContractStellarExpert) {
                                Label("View on Stellar.Expert", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.chimpYellow)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive, action: { showResetAlert = true }) {
                        Text("Reset to Default")
                    }
                    .disabled(isAtDefault)
                }
                
                Section {
                    Button(action: { showLogoutAlert = true }) {
                        Text("Logout")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to logout? Your private key will be removed from this device.")
            }
            .alert("Reset to Default", isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetToDefault()
                }
            } message: {
                Text("This will reset the contract address to the build configuration default. This action cannot be undone.")
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }
    
    private func loadCurrentSettings() {
        contractId = AppConfig.shared.contractId
        originalContractId = AppConfig.shared.contractId
    }
    
    private func saveContractId() {
        AppConfig.shared.contractId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        originalContractId = contractId.trimmingCharacters(in: .whitespacesAndNewlines)
        
        saveStatus = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            saveStatus = nil
        }
    }
    
    private func resetToDefault() {
        // Reset to build configuration defaults
        UserDefaults.standard.removeObject(forKey: "app_contract_id")
        
        contractId = AppConfig.shared.contractId
        originalContractId = AppConfig.shared.contractId
    }
    
    private func openContractStellarExpert() {
        guard !contractId.isEmpty else { return }
        
        let baseUrl: String
        switch currentNetwork {
        case .testnet:
            baseUrl = "https://stellar.expert/explorer/testnet/contract"
        case .mainnet:
            baseUrl = "https://stellar.expert/explorer/public/contract"
        }
        
        let urlString = "\(baseUrl)/\(contractId)"
        guard let url = URL(string: urlString) else { return }
        
        openURL(url)
    }
    
    private func copyContractId() {
        guard !contractId.isEmpty else { return }
        
        UIPasteboard.general.string = contractId
        
        withAnimation {
            contractCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                contractCopied = false
            }
        }
    }
    
    private func logout() {
        do {
            try walletService.logout()
            walletState.checkWalletState()
            } catch {
            // Error handling could be improved with an alert
            print("Logout error: \(error.localizedDescription)")
        }
    }
}
