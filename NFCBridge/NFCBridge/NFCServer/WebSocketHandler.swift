/**
 * WebSocket Protocol Handler
 * Handles WebSocket handshake and frame encoding/decoding
 */

import Foundation
import Network
import CryptoKit

enum WebSocketError: Error {
    case invalidHandshake
    case invalidFrame
    case connectionClosed
}

class WebSocketHandler {
    private var isUpgraded = false
    private var connection: NWConnection
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    /**
     * Handle WebSocket handshake
     */
    func handleHandshake(_ httpRequest: String) throws -> String {
        // Parse HTTP request
        let lines = httpRequest.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw WebSocketError.invalidHandshake
        }
        
        // Extract Sec-WebSocket-Key
        var secWebSocketKey: String?
        for line in lines {
            if line.lowercased().hasPrefix("sec-websocket-key:") {
                let key = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                secWebSocketKey = key
                break
            }
        }
        
        guard let key = secWebSocketKey else {
            throw WebSocketError.invalidHandshake
        }
        
        // Generate Sec-WebSocket-Accept
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let acceptString = key + magicString
        let acceptData = acceptString.data(using: .utf8)!
        let acceptHash = acceptData.sha1()
        let acceptBase64 = acceptHash.base64EncodedString()
        
        // Build HTTP response
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptBase64)\r
        \r
        """
        
        isUpgraded = true
        return response
    }
    
    /**
     * Check if connection is upgraded
     */
    func isConnectionUpgraded() -> Bool {
        return isUpgraded
    }
    
    /**
     * Decode WebSocket frame
     */
    func decodeFrame(_ data: Data) throws -> String? {
        guard data.count >= 2 else {
            throw WebSocketError.invalidFrame
        }
        
        let byte0 = data[0]
        let byte1 = data[1]
        
        // FIN bit (bit 7 of byte 0)
        let fin = (byte0 & 0x80) != 0
        
        // Opcode (bits 0-3 of byte 0)
        let opcode = byte0 & 0x0F
        
        // Check if it's a text frame (opcode 1)
        guard opcode == 0x01 else {
            throw WebSocketError.invalidFrame
        }
        
        // MASK bit (bit 7 of byte 1)
        let masked = (byte1 & 0x80) != 0
        
        // Payload length (bits 0-6 of byte 1)
        var payloadLength = Int(byte1 & 0x7F)
        var maskOffset = 2
        
        // Extended payload length
        if payloadLength == 126 {
            guard data.count >= 4 else {
                throw WebSocketError.invalidFrame
            }
            payloadLength = Int(data[2]) << 8 | Int(data[3])
            maskOffset = 4
        } else if payloadLength == 127 {
            guard data.count >= 10 else {
                throw WebSocketError.invalidFrame
            }
            // For simplicity, we'll handle up to 32-bit lengths
            payloadLength = Int(data[6]) << 24 | Int(data[7]) << 16 | Int(data[8]) << 8 | Int(data[9])
            maskOffset = 10
        }
        
        // Extract mask key (4 bytes)
        var maskKey: [UInt8] = []
        if masked {
            guard data.count >= maskOffset + 4 else {
                throw WebSocketError.invalidFrame
            }
            maskKey = Array(data[maskOffset..<maskOffset + 4])
            maskOffset += 4
        }
        
        // Extract payload
        guard data.count >= maskOffset + payloadLength else {
            throw WebSocketError.invalidFrame
        }
        
        var payload = Array(data[maskOffset..<maskOffset + payloadLength])
        
        // Unmask payload if masked
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        
        // Convert to string
        guard let text = String(data: Data(payload), encoding: .utf8) else {
            throw WebSocketError.invalidFrame
        }
        
        return text
    }
    
    /**
     * Encode WebSocket frame
     */
    func encodeFrame(_ text: String) -> Data {
        guard let textData = text.data(using: .utf8) else {
            return Data()
        }
        
        var frame = Data()
        
        // First byte: FIN (1) + opcode (1 = text frame)
        frame.append(0x81)
        
        // Second byte: MASK (0 for server) + payload length
        let payloadLength = textData.count
        if payloadLength < 126 {
            frame.append(UInt8(payloadLength))
        } else if payloadLength < 65536 {
            frame.append(126)
            frame.append(UInt8((payloadLength >> 8) & 0xFF))
            frame.append(UInt8(payloadLength & 0xFF))
        } else {
            frame.append(127)
            // 64-bit length (but we'll only use 32 bits)
            frame.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
            frame.append(UInt8((payloadLength >> 24) & 0xFF))
            frame.append(UInt8((payloadLength >> 16) & 0xFF))
            frame.append(UInt8((payloadLength >> 8) & 0xFF))
            frame.append(UInt8(payloadLength & 0xFF))
        }
        
        // Append payload (no mask for server-to-client)
        frame.append(textData)
        
        return frame
    }
}

// SHA1 using CryptoKit
extension Data {
    func sha1() -> Data {
        let hash = Insecure.SHA1.hash(data: self)
        return Data(hash)
    }
}
