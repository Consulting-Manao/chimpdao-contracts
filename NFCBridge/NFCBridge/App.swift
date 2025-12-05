/**
 * Main App Entry Point
 * Standalone iOS app for NFC-based NFT minting
 */

import SwiftUI
import Combine
import Foundation

@main
struct NFCBridgeApp: App {
    @StateObject private var appData = AppData()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appData)
        }
    }
}
