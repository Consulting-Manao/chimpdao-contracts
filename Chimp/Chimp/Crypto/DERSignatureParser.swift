/**
 * DER Signature Parser
 * Parses DER-encoded ECDSA signatures from NFC chip
 */

import Foundation

struct SignatureComponents {
    let r: Data  // 32 bytes
    let s: Data  // 32 bytes
}


class DERSignatureParser {
    /// Parse DER-encoded signature to extract r and s components
    /// - Parameter derSignature: DER-encoded signature as Data
    /// - Returns: SignatureComponents with r and s (32 bytes each)
    /// - Throws: AppError if parsing fails
    static func parse(_ derSignature: Data) throws -> SignatureComponents {
        // DER structure: 0x30 || length || 0x02 || r_length || r || 0x02 || s_length || s
        guard derSignature.count >= 8 else {
            throw AppError.derSignature(.parseFailed("Invalid signature length"))
        }
        
        var offset = 0
        
        // Check for 0x30 (SEQUENCE tag)
        guard derSignature[offset] == 0x30 else {
            throw AppError.derSignature(.invalidFormat)
        }
        offset += 1
        
        // Read sequence length
        _ = try readLength(derSignature, offset: &offset)
        
        // Check for 0x02 (INTEGER tag for r)
        guard offset < derSignature.count && derSignature[offset] == 0x02 else {
            throw AppError.derSignature(.invalidComponents)
        }
        offset += 1
        
        // Read r length and value
        let rLength = try readLength(derSignature, offset: &offset)
        guard offset + rLength <= derSignature.count else {
            throw AppError.derSignature(.invalidComponents)
        }
        
        var r = derSignature.subdata(in: offset..<(offset + rLength))
        offset += rLength
        
        // Remove leading zero if present (DER encoding may add padding)
        if r.count > 32 && r[0] == 0x00 {
            r = r.subdata(in: 1..<r.count)
        }
        
        // Pad to 32 bytes if needed
        if r.count < 32 {
            let padding = Data(repeating: 0, count: 32 - r.count)
            r = padding + r
        } else if r.count > 32 {
            // Truncate if somehow longer
            r = r.prefix(32)
        }
        
        // Check for 0x02 (INTEGER tag for s)
        guard offset < derSignature.count && derSignature[offset] == 0x02 else {
            throw AppError.derSignature(.invalidComponents)
        }
        offset += 1
        
        // Read s length and value
        let sLength = try readLength(derSignature, offset: &offset)
        guard offset + sLength <= derSignature.count else {
            throw AppError.derSignature(.invalidComponents)
        }
        
        var s = derSignature.subdata(in: offset..<(offset + sLength))
        offset += sLength
        
        // Remove leading zero if present
        if s.count > 32 && s[0] == 0x00 {
            s = s.subdata(in: 1..<s.count)
        }
        
        // Pad to 32 bytes if needed
        if s.count < 32 {
            let padding = Data(repeating: 0, count: 32 - s.count)
            s = padding + s
        } else if s.count > 32 {
            s = s.prefix(32)
        }
        
        return SignatureComponents(r: r, s: s)
    }
    
    /// Read DER length field
    private static func readLength(_ data: Data, offset: inout Int) throws -> Int {
        guard offset < data.count else {
            throw AppError.derSignature(.invalidFormat)
        }
        
        let firstByte = data[offset]
        offset += 1
        
        if firstByte & 0x80 == 0 {
            // Short form: length is in the byte itself
            return Int(firstByte)
        } else {
            // Long form: number of bytes following indicates length
            let lengthOfLength = Int(firstByte & 0x7F)
            guard lengthOfLength > 0 && lengthOfLength <= 4 else {
                throw AppError.derSignature(.invalidFormat)
            }
            
            guard offset + lengthOfLength <= data.count else {
                throw AppError.derSignature(.invalidFormat)
            }
            
            var length = 0
            for _ in 0..<lengthOfLength {
                length = (length << 8) | Int(data[offset])
                offset += 1
            }
            
            return length
        }
    }
}
