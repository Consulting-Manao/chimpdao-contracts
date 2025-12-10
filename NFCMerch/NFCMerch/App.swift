import SwiftUI
import Combine
import Foundation

@main
struct NFCMerchApp: App {
    @StateObject private var appData = AppData()
    @State private var scannedItem: ScannedItem?
    
    var body: some Scene {
        WindowGroup {
            ContentView(scannedItem: $scannedItem)
                .environmentObject(appData)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "nfmerch" || url.scheme == "stellarmerch" else { return }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2 && pathComponents[0] == "item" {
            let contractId = pathComponents[1]
            let tokenId = pathComponents.count > 2 ? pathComponents[2] : nil
            scannedItem = ScannedItem(contractId: contractId, tokenId: tokenId)
        }
    }
}
