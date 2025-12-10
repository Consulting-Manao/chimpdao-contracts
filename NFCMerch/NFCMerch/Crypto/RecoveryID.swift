import Foundation
import P256K

enum RecoveryIDError: Error {
    case invalidMessageHash
    case invalidSignature
    case invalidPublicKey
    case noMatchFound
    case recoveryFailed
}

func determineRecoveryId(
    messageHash: Data,
    signature: Data,
    expectedPublicKey: String
) async throws -> UInt32 {
    guard messageHash.count == 32 else {
        throw RecoveryIDError.invalidMessageHash
    }
    
    guard signature.count == 64 else {
        throw RecoveryIDError.invalidSignature
    }
    
    let expectedKeyHex = expectedPublicKey.hasPrefix("0x") 
        ? String(expectedPublicKey.dropFirst(2))
        : expectedPublicKey
    
    let expectedKeyBytes = hexToBytes(expectedKeyHex)
    
    guard expectedKeyBytes.count == 65 else {
        throw RecoveryIDError.invalidPublicKey
    }
    
    guard expectedKeyBytes[0] == 0x04 else {
        throw RecoveryIDError.invalidPublicKey
    }
    
    let r = signature.prefix(32)
    let s = signature.suffix(32)
    
    let normalizedS = normalizeS(Data(s))
    
    // Try each recovery ID (0-3)
    for recoveryId in 0...3 {
        if let recovered = try? recoverPublicKeySecp256k1(
            messageHash: messageHash,
            r: Data(r),
            s: normalizedS,
            recoveryId: UInt8(recoveryId)
        ) {
            if recovered == expectedKeyBytes {
                return UInt32(recoveryId)
            }
        }
    }
    
    throw RecoveryIDError.noMatchFound
}

private func recoverPublicKeySecp256k1(
    messageHash: Data,
    r: Data,
    s: Data,
    recoveryId: UInt8
) throws -> Data? {
    // Build the 64-byte compact signature: [r (32 bytes)] || [s (32 bytes)]
    var compactSignature = Data()
    compactSignature.append(r)
    compactSignature.append(s)
    
    guard compactSignature.count == 64 else {
        return nil
    }
    
    do {
        // Create recovery signature from compact format (64 bytes) and recovery ID
        let recoverySignature = try P256K.Recovery.ECDSASignature(
            compactRepresentation: compactSignature,
            recoveryId: Int32(recoveryId)
        )
        
        // Recover public key from signature and message hash (uncompressed format)
        let publicKey = try P256K.Recovery.PublicKey(
            messageHash,
            signature: recoverySignature,
            format: .uncompressed
        )
        
        // Get uncompressed public key (65 bytes, starting with 0x04)
        let uncompressedKey = publicKey.dataRepresentation
        
        guard uncompressedKey.count == 65, uncompressedKey[0] == 0x04 else {
            return nil
        }
        
        return uncompressedKey
    } catch {
        return nil
    }
}

private func normalizeS(_ s: Data) -> Data {
    guard s.count == 32 else { return s }
    
    let curveOrder: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
        0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
        0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
    ]
    
    let halfOrder: [UInt8] = [
        0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
        0xDF, 0xE9, 0x2F, 0x46, 0x68, 0x1B, 0x20, 0xA0
    ]
    
    var sGreaterThanHalf = false
    for i in 0..<32 {
        if s[i] > halfOrder[i] {
            sGreaterThanHalf = true
            break
        } else if s[i] < halfOrder[i] {
            break
        }
    }
    
    if sGreaterThanHalf {
        var normalized = Data(count: 32)
        var borrow: UInt8 = 0
        
        for i in (0..<32).reversed() {
            var diff = Int(curveOrder[i]) - Int(s[i]) - Int(borrow)
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
    
    return s
}

