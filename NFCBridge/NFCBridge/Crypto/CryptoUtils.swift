/**
 * Crypto Utilities
 * Ported from web app crypto.ts
 * Provides hex/bytes conversions and SHA-256 hashing
 */

import Foundation
import CryptoKit

/**
 * Convert hex string to Data
 */
func hexToBytes(_ hex: String) -> Data {
    // Remove 0x prefix if present
    var cleanHex = hex
    if cleanHex.hasPrefix("0x") {
        cleanHex = String(cleanHex.dropFirst(2))
    }
    
    // Ensure even number of characters
    if cleanHex.count % 2 != 0 {
        cleanHex = "0" + cleanHex
    }
    
    var bytes = Data()
    var index = cleanHex.startIndex
    
    while index < cleanHex.endIndex {
        let nextIndex = cleanHex.index(index, offsetBy: 2)
        let byteString = cleanHex[index..<nextIndex]
        if let byte = UInt8(byteString, radix: 16) {
            bytes.append(byte)
        }
        index = nextIndex
    }
    
    return bytes
}

/**
 * Convert Data to hex string
 */
func bytesToHex(_ data: Data) -> String {
    return data.map { String(format: "%02x", $0) }.joined()
}

/**
 * Generate SHA-256 hash of data
 * Uses CryptoKit (built-in on iOS)
 */
func sha256(_ data: Data) -> Data {
    let digest = SHA256.hash(data: data)
    return Data(digest)
}

/**
 * Generate SHA-256 hash of string
 */
func sha256(_ string: String) -> Data {
    let data = string.data(using: .utf8) ?? Data()
    return sha256(data)
}

