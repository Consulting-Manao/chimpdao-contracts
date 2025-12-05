/**
 * Message Handler for WebSocket Server
 * Handles WebSocket upgrade and message routing
 */

import Foundation
import Network

class MessageHandler {
    private let protocolAdapter: ProtocolAdapter
    
    init(protocolAdapter: ProtocolAdapter) {
        self.protocolAdapter = protocolAdapter
    }
    
    /**
     * Handle incoming WebSocket message (text after frame decoding)
     */
    func handleMessage(_ messageText: String, connection: NWConnection, wsHandler: WebSocketHandler, completion: @escaping (String?) -> Void) {
        guard let messageData = messageText.data(using: .utf8),
              let request = try? JSONDecoder().decode(WebSocketRequest.self, from: messageData) else {
            // Invalid JSON, send error response
            let errorResponse = WebSocketResponse(
                type: "error",
                success: false,
                data: nil,
                error: "Invalid request format"
            )
            sendResponse(errorResponse, completion: completion)
            return
        }
        
        // Process request through protocol adapter
        protocolAdapter.processRequest(request) { [weak self] response in
            self?.sendResponse(response, completion: completion)
        }
    }
    
    /**
     * Send response to client (returns JSON string for frame encoding)
     */
    private func sendResponse(_ response: WebSocketResponse, completion: @escaping (String?) -> Void) {
        guard let encoder = try? JSONEncoder().encode(response),
              let jsonString = String(data: encoder, encoding: .utf8) else {
            completion(nil)
            return
        }
        
        completion(jsonString)
    }
}
