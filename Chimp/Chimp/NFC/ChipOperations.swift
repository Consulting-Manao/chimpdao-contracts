import Foundation
import CoreNFC

/// Utility class for chip operations (reading public key, signing)
final class ChipOperations {
    /// Read public key from chip
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - keyIndex: Key index to use (default: 1)
    /// - Returns: Public key as hex string (65 bytes, uncompressed format with 0x04 prefix)
    /// - Throws: AppError if reading fails
    static func readChipPublicKey(tag: NFCISO7816Tag, session: NFCTagReaderSession, keyIndex: UInt8 = 0x01) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGetKey(key_index: keyIndex) { success, response, error, session in
                if success, let response = response, response.count >= 73 {
                    // Extract public key (skip first 9 bytes: 4 bytes global counter + 4 bytes signature counter + 1 byte 0x04)
                    let publicKeyData = response.subdata(in: 9..<73) // 64 bytes of public key
                    // Add 0x04 prefix for uncompressed format
                    var fullPublicKey = Data([0x04])
                    fullPublicKey.append(publicKeyData)
                    let publicKeyHex = fullPublicKey.map { String(format: "%02x", $0) }.joined()
                    continuation.resume(returning: publicKeyHex)
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }
    
    /// Sign message with chip
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - messageHash: 32-byte message hash to sign
    ///   - keyIndex: Key index to use (default: 1)
    /// - Returns: SignatureComponents with r and s values
    /// - Throws: AppError if signing fails
    static func signWithChip(tag: NFCISO7816Tag, session: NFCTagReaderSession, messageHash: Data, keyIndex: UInt8 = 0x01) async throws -> SignatureComponents {
        guard messageHash.count == 32 else {
            throw AppError.crypto(.invalidOperation("Invalid message hash. This is an internal error. Please try again."))
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let commandHandler = BlockchainCommandHandler(tag_iso7816: tag, reader_session: session)
            commandHandler.ActionGenerateSignature(key_index: keyIndex, message_digest: messageHash) { success, response, error, session in
                if success, let response = response, response.count >= 8 {
                    // Response format: 4 bytes global counter + 4 bytes key counter + DER signature
                    let derSignature = response.subdata(in: 8..<response.count)
                    
                    do {
                        let components = try DERSignatureParser.parse(derSignature)
                        continuation.resume(returning: components)
                    } catch {
                        continuation.resume(throwing: AppError.derSignature(.parseFailed(error.localizedDescription)))
                    }
                } else {
                    continuation.resume(throwing: AppError.nfc(.chipError(error ?? "Unknown error")))
                }
            }
        }
    }
}

