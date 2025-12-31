import SwiftUI

struct LoginView: View {
    @ObservedObject var walletState: WalletState
    @State private var secretKey: String = ""
    @State private var isSecure: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    private let walletService = WalletService()

    var body: some View {
        NavigationView {
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
                        .padding(.bottom, 20)
                    
                    // Title
                    Text("Welcome to Chimp")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Connect your Stellar wallet")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 40)
                    
                    // Secret Key Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Secret Key")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if isSecure {
                                SecureField("Enter your Stellar secret key (S...)", text: $secretKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                TextField("Enter your Stellar secret key (S...)", text: $secretKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            Button(action: { isSecure.toggle() }) {
                                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.red)
                            .padding(.horizontal, 20)
                    }
                    
                    // Login Button
                    Button(action: login) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Login")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.chimpYellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading || secretKey.isEmpty)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
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
