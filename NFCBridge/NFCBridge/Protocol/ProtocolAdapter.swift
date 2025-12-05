/**
 * Protocol Adapter
 * Translates between web app WebSocket protocol and NFC operations
 * Matches desktop server protocol exactly
 */

import Foundation

struct WebSocketRequest: Codable {
    let type: String
    let data: RequestData?
    
    struct RequestData: Codable {
        let messageDigest: String?
        
        enum CodingKeys: String, CodingKey {
            case messageDigest
        }
    }
}

struct WebSocketResponse: Codable {
    let type: String
    let success: Bool
    let data: ResponseData?
    let error: String?
    
    struct ResponseData: Codable {
        let publicKey: String?
        let r: String?
        let s: String?
        let v: Int?
        let recoveryId: Int?
        let readerConnected: Bool?
        let chipPresent: Bool?
        let readerName: String?
    }
}

class ProtocolAdapter {
    private let nfcService: NFCService
    private var chipPresent: Bool = false
    
    init(nfcService: NFCService) {
        self.nfcService = nfcService
    }
    
    /**
     * Process incoming request from web app
     */
    func processRequest(_ request: WebSocketRequest, completion: @escaping (WebSocketResponse) -> Void) {
        switch request.type {
        case "status":
            handleStatusRequest(completion: completion)
            
        case "read-pubkey":
            handleReadPublicKeyRequest(completion: completion)
            
        case "sign":
            guard let messageDigestHex = request.data?.messageDigest else {
                completion(createErrorResponse("Missing messageDigest in sign request"))
                return
            }
            handleSignRequest(messageDigestHex: messageDigestHex, completion: completion)
            
        default:
            completion(createErrorResponse("Unknown request type: \(request.type)"))
        }
    }
    
    /**
     * Handle status request
     */
    private func handleStatusRequest(completion: @escaping (WebSocketResponse) -> Void) {
        // For status check, we don't need to actually read the chip
        // Just return that reader is connected (chip presence will be determined on actual operations)
        // This avoids triggering NFC session unnecessarily
        completion(WebSocketResponse(
            type: "status",
            success: true,
            data: WebSocketResponse.ResponseData(
                publicKey: nil,
                r: nil,
                s: nil,
                v: nil,
                recoveryId: nil,
                readerConnected: true,
                chipPresent: chipPresent, // Last known state
                readerName: "iOS Core NFC"
            ),
            error: nil
        ))
    }
    
    /**
     * Handle read public key request
     */
    private func handleReadPublicKeyRequest(completion: @escaping (WebSocketResponse) -> Void) {
        nfcService.readPublicKey { result in
            switch result {
            case .success(let publicKey):
                chipPresent = true
                completion(WebSocketResponse(
                    type: "pubkey",
                    success: true,
                    data: WebSocketResponse.ResponseData(
                        publicKey: publicKey,
                        r: nil,
                        s: nil,
                        v: nil,
                        recoveryId: nil,
                        readerConnected: nil,
                        chipPresent: nil,
                        readerName: nil
                    ),
                    error: nil
                ))
                
            case .failure(let error):
                completion(createErrorResponse("Failed to read public key: \(error.localizedDescription)"))
            }
        }
    }
    
    /**
     * Handle sign request
     */
    private func handleSignRequest(messageDigestHex: String, completion: @escaping (WebSocketResponse) -> Void) {
        // Validate hex string
        guard messageDigestHex.count == 64,
              let messageHash = hexStringToData(messageDigestHex),
              messageHash.count == 32 else {
            completion(createErrorResponse("Invalid message digest (must be 32 bytes / 64 hex chars)"))
            return
        }
        
        nfcService.signMessage(messageHash: messageHash) { result in
            switch result {
            case .success(let (r, s, recoveryId)):
                completion(WebSocketResponse(
                    type: "signature",
                    success: true,
                    data: WebSocketResponse.ResponseData(
                        publicKey: nil,
                        r: r,
                        s: s,
                        v: recoveryId,
                        recoveryId: recoveryId,
                        readerConnected: nil,
                        chipPresent: nil,
                        readerName: nil
                    ),
                    error: nil
                ))
                
            case .failure(let error):
                completion(createErrorResponse("Failed to sign message: \(error.localizedDescription)"))
            }
        }
    }
    
    /**
     * Create error response
     */
    private func createErrorResponse(_ message: String) -> WebSocketResponse {
        return WebSocketResponse(
            type: "error",
            success: false,
            data: nil,
            error: message
        )
    }
    
    /**
     * Convert hex string to Data
     */
    private func hexStringToData(_ hex: String) -> Data? {
        let len = hex.count / 2
        var data = Data(capacity: len)
        
        for i in 0..<len {
            let start = hex.index(hex.startIndex, offsetBy: i * 2)
            let end = hex.index(start, offsetBy: 2)
            let bytes = hex[start..<end]
            
            if let byte = UInt8(bytes, radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
        }
        
        return data
    }
}
