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
 * Create SEP-53 compliant auth message
 * 
 * Format: network_hash || contract_id || function_name || args || valid_until_ledger
 * 
 * - network_hash: SHA-256 hash of network passphrase (32 bytes)
 * - contract_id: Contract address in hex, converted to bytes (32 bytes)
 * - function_name: Function name as UTF-8 bytes
 * - args: JSON-encoded arguments as UTF-8 bytes
 * - valid_until_ledger: Ledger sequence number (4 bytes, big-endian)
 * 
 * Returns both the message and its hash
 */
func createSEP53Message(
    contractId: String,
    functionName: String,
    args: [Any],
    validUntilLedger: UInt32,
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
    
    // 5. Valid until ledger (4 bytes, big-endian)
    var ledgerBytes = Data(count: 4)
    ledgerBytes[0] = UInt8((validUntilLedger >> 24) & 0xFF)
    ledgerBytes[1] = UInt8((validUntilLedger >> 16) & 0xFF)
    ledgerBytes[2] = UInt8((validUntilLedger >> 8) & 0xFF)
    ledgerBytes[3] = UInt8(validUntilLedger & 0xFF)
    parts.append(ledgerBytes)
    
    // 6. Concatenate all parts
    let totalLength = parts.reduce(0) { $0 + $1.count }
    var combined = Data(capacity: totalLength)
    for part in parts {
        combined.append(part)
    }
    
    // 7. Hash the combined message
    let messageHash = sha256(combined)
    guard messageHash.count == 32 else {
        throw SEP53Error.hashGenerationFailed
    }
    
    return SEP53MessageResult(message: combined, messageHash: messageHash)
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

