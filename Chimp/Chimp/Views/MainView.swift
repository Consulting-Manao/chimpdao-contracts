import SwiftUI
import Combine

@MainActor
class WalletState: ObservableObject {
    @Published var hasWallet: Bool = false
    private let walletService = WalletService.shared
    
    init() {
        checkWalletState()
    }
    
    func checkWalletState() {
        hasWallet = walletService.getStoredWallet() != nil
    }
}

struct MainView: View {
    @StateObject private var walletState = WalletState()
    
    var body: some View {
        Group {
            if walletState.hasWallet {
                MainTabView(walletState: walletState)
            } else {
                LoginView(walletState: walletState)
            }
        }
    }
}

