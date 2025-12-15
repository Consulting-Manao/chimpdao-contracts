/**
 * Crypto Utilities
 * Provides SEP-53 message creation and signature normalization
 */

import Foundation
import CryptoKit
import stellarsdk

class CryptoUtils {
    /// Create SEP-53 compliant auth message
    /// - Parameters:
    ///   - contractId: Contract ID (hex string, 32 bytes)
    ///   - functionName: Function name to call
    ///   - args: Function arguments (will be JSON encoded)
    ///   - nonce: Nonce value
    ///   - networkPassphrase: Network passphrase
    /// - Returns: Tuple of (message: Data, messageHash: Data)
    static func createSEP53Message(
        contractId: String,
        functionName: String,
        args: [Any],
        nonce: UInt32,
        networkPassphrase: String
    ) throws -> (message: Data, messageHash: Data) {
        var parts: [Data] = []
        
        // Network passphrase hash (32 bytes)
        let networkData = networkPassphrase.data(using: .utf8) ?? Data()
        let networkHash = Data(SHA256.hash(data: networkData))
        parts.append(networkHash)
        
        // Contract ID (32 bytes)
        // Stellar contract IDs are base32 encoded addresses (56 chars starting with 'C')
        // Decode from base32 to get the 32-byte contract ID
        // Format: version (1 byte) + contract ID (32 bytes) + checksum (2 bytes) = 35 bytes
        let contractIdData: Data
        if contractId.hasPrefix("C") && contractId.count == 56 {
            // This is a Stellar contract address - decode from base32
            contractIdData = try decodeStellarContractId(contractId)
            print("CryptoUtils: Decoded contract ID from address: \(contractIdData.map { String(format: "%02x", $0) }.joined())")
        } else if contractId.count == 64 {
            // This might be a hex string (64 hex chars = 32 bytes)
            guard let hexData = Data(hexString: contractId), hexData.count == 32 else {
                throw AppError.crypto(.invalidKey("Invalid contract ID format"))
            }
            contractIdData = hexData
            print("CryptoUtils: Using hex contract ID: \(contractIdData.map { String(format: "%02x", $0) }.joined())")
        } else {
            throw AppError.crypto(.invalidKey("Invalid contract ID format"))
        }
        guard contractIdData.count == 32 else {
            print("CryptoUtils: ERROR: Contract ID data length is \(contractIdData.count), expected 32")
            throw AppError.crypto(.invalidKey("Invalid contract ID format"))
        }
        parts.append(contractIdData)
        
        // Function name
        guard let functionNameData = functionName.data(using: .utf8) else {
            throw AppError.crypto(.invalidOperation("Invalid function name"))
        }
        parts.append(functionNameData)
        
        // Args (JSON encoded)
        let argsJson = try JSONSerialization.data(withJSONObject: args)
        parts.append(argsJson)
        
        // Concatenate all parts (without nonce)
        var message = Data()
        for part in parts {
            message.append(part)
        }
        
        // Append nonce XDR format
        // ScVal U32: 4 bytes discriminant (3) + 4 bytes value (big-endian)
        // Format matches Soroban's to_xdr() method for u32
        // This matches the TypeScript implementation: view.setUint32(0, 3, false); view.setUint32(4, nonce, false);
        var nonceXdr = Data()
        nonceXdr.append(contentsOf: [0x00, 0x00, 0x00, 0x03]) // U32 discriminant (big-endian uint32: 3)
        // Append nonce value as big-endian bytes (4 bytes)
        let nonceByte1 = UInt8((nonce >> 24) & 0xFF)
        let nonceByte2 = UInt8((nonce >> 16) & 0xFF)
        let nonceByte3 = UInt8((nonce >> 8) & 0xFF)
        let nonceByte4 = UInt8(nonce & 0xFF)
        nonceXdr.append(contentsOf: [nonceByte1, nonceByte2, nonceByte3, nonceByte4])
        
        // Message with nonce for hashing
        var messageWithNonce = message
        messageWithNonce.append(nonceXdr)
        
        // Hash the message with nonce
        let messageHash = Data(SHA256.hash(data: messageWithNonce))
        
        return (message: message, messageHash: messageHash)
    }
    
    /// Normalize the S value of an ECDSA signature
    /// Soroban's secp256k1_recover requires normalized S values
    /// - Parameter s: S value as 32-byte Data (big-endian)
    /// - Returns: Normalized S value (32 bytes, big-endian)
    static func normalizeS(_ s: Data) -> Data {
        guard s.count == 32 else {
            return s
        }
        
        // secp256k1 curve order n (big-endian)
        let curveOrder: [UInt8] = [
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
            0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
            0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
        ]
        
        // Half order = n / 2
        // Matching JS implementation in src/util/crypto.ts
        let halfOrder: [UInt8] = [
            0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D
        ]
        
        // Compare s with halfOrder (big-endian)
        var sGreaterThanHalf = false
        for i in 0..<32 {
            if s[i] > halfOrder[i] {
                sGreaterThanHalf = true
                break
            } else if s[i] < halfOrder[i] {
                break
            }
        }
        
        // If s > halfOrder, normalize: s = n - s
        // Matching JS implementation exactly: src/util/crypto.ts normalizeS()
        if sGreaterThanHalf {
            var normalized = Data(count: 32)
            var borrow = 0
            
            for i in (0..<32).reversed() {
                var diff = Int(curveOrder[i]) - Int(s[i]) - borrow
                if diff < 0 {
                    diff += 256
                    borrow = 1
                } else {
                    borrow = 0
                }
                normalized[i] = UInt8(diff)
            }
            
            return normalized
        }
        
        // s is already normalized
        return s
    }
    
    /// Decode Stellar contract ID from base32 address format
    /// Contract addresses are 56 characters starting with 'C'
    /// Returns the 32-byte contract ID
    private static func decodeStellarContractId(_ contractAddress: String) throws -> Data {
        // Stellar contract IDs use base32 encoding with custom alphabet
        // The format is: version byte (1) + contract ID (32 bytes) + checksum (2 bytes) = 35 bytes
        // Base32 encoded: 35 * 8 / 5 = 56 characters
        
        // Use stellarsdk to decode if available, otherwise manual base32 decode
        // For now, we'll use a simple approach: the SDK should handle this
        // But we need the raw 32 bytes from the contract address
        
        // Try using stellarsdk's Address or Contract to decode
        // Actually, we can use the contract ID directly from the SDK
        // But for SEP-53, we need the raw 32-byte contract ID
        
        // Manual base32 decode (Stellar uses custom base32)
        let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var value: UInt64 = 0  // Use UInt64 to avoid overflow
        var result = Data()
        
        for char in contractAddress.uppercased() {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                throw AppError.crypto(.invalidKey("Invalid contract ID format"))
            }
            let charValue = UInt64(base32Alphabet.distance(from: base32Alphabet.startIndex, to: index))
            
            value = (value << 5) | charValue
            bits += 5
            
            if bits >= 8 {
                let byte = UInt8((value >> (bits - 8)) & 0xFF)
                result.append(byte)
                value = value & ((1 << (bits - 8)) - 1)  // Keep remaining bits
                bits -= 8
            }
        }
        
        // Stellar contract address: version (1 byte) + contract ID (32 bytes) + checksum (2 bytes) = 35 bytes
        // After base32 decode: 35 bytes
        // We need bytes 1-32 (skip version byte, take 32 bytes, skip checksum)
        guard result.count >= 35 else {
            throw AppError.crypto(.invalidKey("Invalid contract ID format"))
        }
        
        // Extract the 32-byte contract ID (skip first byte, take next 32 bytes)
        let contractIdBytes = result.subdata(in: 1..<33)
        return contractIdBytes
    }
}

