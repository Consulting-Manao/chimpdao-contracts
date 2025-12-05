/**
 * Main UI View
 * Simple status display for bridge app
 */

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("NFC Bridge")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if appState.serverRunning {
                VStack(spacing: 10) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                        Text("Server Running")
                            .font(.headline)
                    }
                    
                    Text("Listening on localhost:8080")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if appState.clientCount > 0 {
                        Text("\(appState.clientCount) client(s) connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 5)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                        Text("Server Stopped")
                            .font(.headline)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }
            
            Text("Keep this app running in the background")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
