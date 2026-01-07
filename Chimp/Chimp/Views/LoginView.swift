import SwiftUI

struct LoginView: View {
    @ObservedObject var walletState: WalletState
    @State private var secretKey: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    private let walletService = WalletService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.chimpBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Logo
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .padding(.bottom, 16)
                        .accessibilityLabel("Chi//mp logo")
                    
                    // Title
                    Text("Welcome to Chi//mp")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .accessibilityAddTraits(.isHeader)
                    
                    Text("Connect your Stellar wallet")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 32)
                    
                    // Secret Key Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Secret Key")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your Stellar secret key (S...)", text: $secretKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .accessibilityLabel("Secret key input")
                            .accessibilityHint("Enter your 56-character Stellar secret key starting with S")
                    }
                    .padding(.horizontal, 20)
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                            .accessibilityLabel("Error: \(error)")
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    
                    // Login Button
                    Button(action: login) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Text("Login")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading || secretKey.isEmpty)
                    .padding(.horizontal, 20)
                    .accessibilityLabel(isLoading ? "Logging in" : "Login")
                    .accessibilityHint("Connect your Stellar wallet with your secret key")
                    
                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func login() {
        guard !secretKey.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await walletService.loadWalletFromSecretKey(secretKey)
                await MainActor.run {
                    isLoading = false
                    walletState.checkWalletState()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
