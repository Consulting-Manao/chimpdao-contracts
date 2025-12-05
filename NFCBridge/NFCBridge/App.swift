/**
 * Main App Entry Point
 */

import SwiftUI
import Combine
import Foundation

@main
struct NFCBridgeApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

class AppState: ObservableObject {
    let nfcService = NFCService()
    let nfcServer: NFCServer
    @Published var serverRunning = false
    @Published var clientCount = 0
    
    init() {
        self.nfcServer = NFCServer(nfcService: nfcService)
        setupServer()
    }
    
    private func setupServer() {
        nfcServer.delegate = self
        nfcServer.start()
    }
}

extension AppState: NFCServerDelegate {
    func serverDidStart() {
        DispatchQueue.main.async {
            self.serverRunning = true
        }
    }
    
    func serverDidStop() {
        DispatchQueue.main.async {
            self.serverRunning = false
        }
    }
    
    func clientDidConnect() {
        DispatchQueue.main.async {
            self.clientCount += 1
        }
    }
    
    func clientDidDisconnect() {
        DispatchQueue.main.async {
            self.clientCount = max(0, self.clientCount - 1)
        }
    }
}
