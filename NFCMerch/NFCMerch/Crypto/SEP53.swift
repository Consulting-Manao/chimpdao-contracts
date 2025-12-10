/**
 * SEP-53 Message Creation
 * Ported from web app crypto.ts
 * Creates SEP-53 compliant auth messages for contract function authorization
 */

import Foundation

/**
 * SEP-53 Message Creation Result
 */
struct SEP53MessageResult {
    let message: Data          // Original message bytes
    let messageHash: Data      // SHA-256 hash of message (32 bytes)
}

/**
 * Create SEP-53 compliant auth message (without nonce)
 * The nonce is appended to the message before hashing for signature
 * 
 * Format: network_hash || contract_id || function_name || args
 * Nonce is appended separately before hashing
 * 
 * - network_hash: SHA-256 hash of network passphrase (32 bytes)
 * - contract_id: Contract address in hex, converted to bytes (32 bytes)
 * - function_name: Function name as UTF-8 bytes
 * - args: JSON-encoded arguments as UTF-8 bytes
 * 
 * Returns both the message (without nonce) and the hash of (message + nonce)
 */
func createSEP53Message(
    contractId: String,
    functionName: String,
    args: [Any],
    nonce: UInt32,
    networkPassphrase: String
) throws -> SEP53MessageResult {
    var parts: [Data] = []
    
    // 1. Network passphrase hash (32 bytes)
    let networkHash = sha256(networkPassphrase)
    guard networkHash.count == 32 else {
        throw SEP53Error.invalidNetworkHash
    }
    parts.append(networkHash)
    
    // 2. Contract ID (32 bytes)
    let contractIdBytes = hexToBytes(contractId)
    guard contractIdBytes.count == 32 else {
        throw SEP53Error.invalidContractId
    }
    parts.append(contractIdBytes)
    
    // 3. Function name (UTF-8)
    guard let functionNameBytes = functionName.data(using: .utf8) else {
        throw SEP53Error.invalidFunctionName
    }
    parts.append(functionNameBytes)
    
    // 4. Args (JSON encoded as UTF-8)
    // Use JSONSerialization to handle [Any] array
    guard JSONSerialization.isValidJSONObject(args),
          let argsJson = try? JSONSerialization.data(withJSONObject: args, options: []),
          let argsString = String(data: argsJson, encoding: .utf8),
          let argsBytes = argsString.data(using: .utf8) else {
        throw SEP53Error.invalidArgs
    }
    parts.append(argsBytes)
    
    // 5. Concatenate all parts (without nonce)
    let totalLength = parts.reduce(0) { $0 + $1.count }
    var message = Data(capacity: totalLength)
    for part in parts {
        message.append(part)
    }
    
    // 6. Append nonce to message before hashing
    // IMPORTANT: Must match contract's nonce.to_xdr() which produces 8 bytes:
    // - 4 bytes: ScVal U32 discriminant (0x00000003 = 3)
    // - 4 bytes: big-endian u32 value
    var nonceXdrBytes = Data(count: 8)
    // First 4 bytes: ScVal U32 discriminant = 3 (big-endian)
    nonceXdrBytes[0] = 0x00
    nonceXdrBytes[1] = 0x00
    nonceXdrBytes[2] = 0x00
    nonceXdrBytes[3] = 0x03
    // Last 4 bytes: nonce value (big-endian)
    nonceXdrBytes[4] = UInt8((nonce >> 24) & 0xFF)
    nonceXdrBytes[5] = UInt8((nonce >> 16) & 0xFF)
    nonceXdrBytes[6] = UInt8((nonce >> 8) & 0xFF)
    nonceXdrBytes[7] = UInt8(nonce & 0xFF)
    
    var messageWithNonce = message
    messageWithNonce.append(nonceXdrBytes)
    
    // 7. Hash the message with nonce
    let messageHash = sha256(messageWithNonce)
    guard messageHash.count == 32 else {
        throw SEP53Error.hashGenerationFailed
    }
    
    return SEP53MessageResult(message: message, messageHash: messageHash)
}

/**
 * SEP-53 Error Types
 */
enum SEP53Error: Error, LocalizedError {
    case invalidNetworkHash
    case invalidContractId
    case invalidFunctionName
    case invalidArgs
    case hashGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidNetworkHash:
            return "Network hash must be exactly 32 bytes"
        case .invalidContractId:
            return "Contract ID must be exactly 32 bytes (64 hex characters)"
        case .invalidFunctionName:
            return "Function name must be valid UTF-8"
        case .invalidArgs:
            return "Failed to encode arguments as JSON"
        case .hashGenerationFailed:
            return "Failed to generate message hash"
        }
    }
}

