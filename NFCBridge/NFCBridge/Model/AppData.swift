/**
 * App State Model
 * Observable state manager following SwiftBasicPay pattern
 */

import Foundation
import Combine

@MainActor
class AppData: ObservableObject {
    // NFC
    let nfcService = NFCService()
    
    // Services
    let blockchainService = BlockchainService()
    let walletService = WalletService()
    
    // Wallet state
    @Published var walletConnection: WalletConnection?
    var isWalletConnected: Bool {
        walletConnection != nil
    }
    
    // Mint state
    @Published var minting = false
    @Published var mintError: String?
    @Published var lastMintedTokenId: String?
    
    init() {
        // Check for stored wallet
        walletConnection = walletService.getStoredWallet()
    }
}

