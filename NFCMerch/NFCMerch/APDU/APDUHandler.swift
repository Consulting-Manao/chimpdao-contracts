/**
 * APDU Command Handler
 * Processes APDU commands and responses from SECORA Blockchain chip
 */

import Foundation

struct APDUResponse {
    let data: Data
    let statusWord: UInt16 // SW1 SW2
    
    init?(rawResponse: Data) {
        guard rawResponse.count >= 2 else {
            return nil
        }
        
        let statusBytes = rawResponse.suffix(2)
        let sw1 = statusBytes[statusBytes.startIndex]
        let sw2 = statusBytes[statusBytes.startIndex + 1]
        self.statusWord = UInt16(sw1) << 8 | UInt16(sw2)
        
        // Data is everything except the last 2 status bytes
        if rawResponse.count > 2 {
            self.data = rawResponse.prefix(rawResponse.count - 2)
        } else {
            self.data = Data()
        }
    }
    
    var isSuccess: Bool {
        return statusWord == 0x9000
    }
}

class APDUHandler {
    /**
     * Parse public key from GET_KEY_INFO response
     * Expected format: Uncompressed public key (65 bytes: 0x04 + 64 bytes)
     */
    static func parsePublicKey(from response: Data) -> String? {
        // SECORA chip returns uncompressed public key (65 bytes)
        // Format: 0x04 followed by 64 bytes (x, y coordinates)
        guard response.count >= 65 else {
            return nil
        }
        
        // Verify it starts with 0x04 (uncompressed point indicator)
        guard response[0] == 0x04 else {
            return nil
        }
        
        // Convert to hex string (remove leading 0x04 is not necessary - include it)
        let hexString = response.map { String(format: "%02x", $0) }.joined()
        return hexString
    }
    
    /**
     * Parse signature from GENERATE_SIGNATURE response
     * Expected format: DER-encoded ECDSA signature
     * Returns: (r, s, recoveryId)
     */
    static func parseSignature(from response: Data) -> (r: String, s: String, recoveryId: Int)? {
        // The response contains DER-encoded signature
        // Parse DER format: SEQUENCE { INTEGER r, INTEGER s }
        
        guard let (r, s) = parseDERSignature(response) else {
            return nil
        }
        
        // Recovery ID 1 (hardcoded for Infineon SECORA chips)
        let recoveryId = 1
        
        return (r: r, s: s, recoveryId: recoveryId)
    }
    
    /**
     * Parse DER-encoded ECDSA signature
     * Format: 0x30 [length] 0x02 [r_length] [r_bytes] 0x02 [s_length] [s_bytes]
     */
    private static func parseDERSignature(_ der: Data) -> (r: String, s: String)? {
        guard der.count >= 8 else {
            return nil
        }
        
        var offset = 0
        
        // 0x30: SEQUENCE
        guard der[offset] == 0x30 else {
            return nil
        }
        offset += 1
        
        // Skip total length
        _ = der[offset] // seqLength - not used, just advancing offset
        offset += 1
        
        // 0x02: INTEGER (r)
        guard der[offset] == 0x02 else {
            return nil
        }
        offset += 1
        
        let rLength = Int(der[offset])
        offset += 1
        
        var rBytes = der[offset..<offset + rLength]
        offset += rLength
        
        // Remove leading 0x00 if present (DER adds it when high bit is set)
        if rBytes.first == 0x00 {
            rBytes = rBytes.dropFirst()
        }
        
        // 0x02: INTEGER (s)
        guard der[offset] == 0x02 else {
            return nil
        }
        offset += 1
        
        let sLength = Int(der[offset])
        offset += 1
        
        var sBytes = der[offset..<offset + sLength]
        offset += sLength
        
        // Remove leading 0x00 if present
        if sBytes.first == 0x00 {
            sBytes = sBytes.dropFirst()
        }
        
        // Normalize s to low form (required by Stellar/Soroban)
        let normalizedS = normalizeS(Data(sBytes))
        
        // Pad to 32 bytes each
        let rPadded = padTo32Bytes(Data(rBytes))
        let sPadded = padTo32Bytes(normalizedS)
        
        // Convert to hex strings
        let rHex = rPadded.map { String(format: "%02x", $0) }.joined()
        let sHex = sPadded.map { String(format: "%02x", $0) }.joined()
        
        return (r: rHex, s: sHex)
    }
    
    /**
     * Normalize s to low form (s <= n/2)
     * secp256k1 curve order: n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
     */
    private static func normalizeS(_ s: Data) -> Data {
        let halfOrder = Data([0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                              0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                              0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
                              0xDF, 0xE9, 0x2F, 0x46, 0x68, 0x1B, 0x20, 0xA0])
        
        // Compare s with halfOrder
        if compareBytes(s, halfOrder) > 0 {
            // s > n/2, so s = n - s
            let order = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                              0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
                              0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
                              0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41])
            
            // Subtract: order - s
            var result = Data(repeating: 0, count: 32)
            var borrow = false
            for i in (0..<32).reversed() {
                let sVal = i < s.count ? s[i] : 0
                let orderVal = order[i]
                var diff = Int(orderVal) - Int(sVal)
                if borrow {
                    diff -= 1
                }
                borrow = diff < 0
                if borrow {
                    diff += 256
                }
                result[i] = UInt8(diff)
            }
            return result
        }
        
        return s
    }
    
    /**
     * Compare two byte arrays (big-endian)
     * Returns: -1 if a < b, 0 if a == b, 1 if a > b
     */
    private static func compareBytes(_ a: Data, _ b: Data) -> Int {
        let maxLength = max(a.count, b.count)
        for i in 0..<maxLength {
            let aVal = i < a.count ? a[i] : 0
            let bVal = i < b.count ? b[i] : 0
            if aVal < bVal {
                return -1
            } else if aVal > bVal {
                return 1
            }
        }
        return 0
    }
    
    /**
     * Pad data to exactly 32 bytes
     */
    private static func padTo32Bytes(_ data: Data) -> Data {
        guard data.count <= 32 else {
            fatalError("Data exceeds 32 bytes")
        }
        
        if data.count == 32 {
            return data
        }
        
        var padded = Data(repeating: 0, count: 32)
        let offset = 32 - data.count
        padded.replaceSubrange(offset..<32, with: data)
        return padded
    }
}
