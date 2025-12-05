/**
 * Main UI View
 * Routes to WalletConnectView or MintView based on wallet connection status
 */

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appData: AppData
    
    var body: some View {
        Group {
            if appData.isWalletConnected {
                MintView()
            } else {
                WalletConnectView()
            }
        }
    }
}
