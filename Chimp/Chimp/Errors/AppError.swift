/**
 * Unified Error Handling System
 *
 * This file contains the complete error hierarchy for the Chimp app.
 * All errors should be defined here to ensure consistency and maintainability.
 */

import Foundation

/// Top-level error enum for the entire application
/// All app errors should be represented as cases of this enum
enum AppError: Error, LocalizedError {
    // MARK: - Blockchain Errors

    /// Errors related to blockchain operations and smart contracts
    case blockchain(BlockchainError)

    // MARK: - Service Errors

    /// Errors related to NFC operations
    case nfc(NFCError)

    /// Errors related to wallet operations
    case wallet(WalletError)

    /// Errors related to IPFS operations
    case ipfs(IPFSError)

    /// Errors related to secure storage operations
    case secureStorage(SecureKeyStorageError)

    /// Errors related to cryptographic operations
    case crypto(CryptoError)

    /// Errors related to DER signature parsing
    case derSignature(DERSignatureParserError)

    // MARK: - UI Errors

    /// Errors related to NFT display and loading
    case nft(NFTError)

    // MARK: - Generic Errors

    /// Unexpected errors that don't fit other categories
    case unexpected(String)

    /// Network connectivity errors
    case network(String)

    /// User input validation errors
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .blockchain(let error):
            return error.localizedDescription
        case .nfc(let error):
            return error.localizedDescription
        case .wallet(let error):
            return error.localizedDescription
        case .ipfs(let error):
            return error.localizedDescription
        case .secureStorage(let error):
            return error.localizedDescription
        case .crypto(let error):
            return error.localizedDescription
        case .derSignature(let error):
            return error.localizedDescription
        case .nft(let error):
            return error.localizedDescription
        case .unexpected(let message):
            return "An unexpected error occurred: \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .validation(let message):
            return message
        }
    }
}

// MARK: - Blockchain Errors

enum BlockchainError: LocalizedError {
    // MARK: - Contract Errors

    /// Smart contract execution errors with specific error codes
    case contract(ContractError)

    // MARK: - Transaction Errors

    /// Transaction was rejected by the network
    case transactionRejected(String?)

    /// Transaction failed during execution
    case transactionFailed

    /// Transaction submission timed out
    case transactionTimeout

    // MARK: - Network Errors

    /// Invalid response from blockchain network
    case invalidResponse

    /// Network connectivity issues
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .contract(let contractError):
            return contractError.localizedDescription
        case .transactionRejected(let message):
            return message ?? "Transaction rejected. Check network."
        case .transactionFailed:
            return "Transaction failed. Check funds and try again."
        case .transactionTimeout:
            return "Transaction timed out. Check status later."
        case .invalidResponse:
            return "Invalid network response."
        case .networkError(let message):
            return "Blockchain network error: \(message)"
        }
    }
}

enum ContractError: LocalizedError {
    // Error code 200: NonExistentToken - Indicates a non-existent token_id
    case nonExistentToken

    // Error code 201: IncorrectOwner - Indicates an error related to the ownership over a particular token (used in transfers)
    case incorrectOwner

    // Error code 205: MathOverflow - Indicates overflow when adding two values
    case mathOverflow

    // Error code 206: TokenIDsAreDepleted - Indicates all possible token_ids are already in use
    case tokenIDsAreDepleted

    // Error code 207: InvalidAmount - Indicates an invalid amount to batch mint in consecutive extension
    case invalidAmount

    // Error code 210: TokenAlreadyMinted - Indicates the token was already minted
    case tokenAlreadyMinted

    // Error code 212: InvalidRoyaltyAmount - Indicates the royalty amount is higher than 10_000 (100%) basis points
    case invalidRoyaltyAmount

    // Error code 214: InvalidSignature - Indicates an invalid signature
    case invalidSignature

    // Error code 215: TokenNotClaimed - Indicates the token exists but has not been claimed yet
    case tokenNotClaimed

    // Unknown error code from contract
    case unknown(code: UInt32)

    var errorDescription: String? {
        switch self {
        case .nonExistentToken:
            return "This token does not exist."
        case .incorrectOwner:
            return "You do not own this token."
        case .mathOverflow:
            return "Calculation error occurred."
        case .tokenIDsAreDepleted:
            return "No more tokens can be minted."
        case .invalidAmount:
            return "Invalid amount specified."
        case .tokenAlreadyMinted:
            return "NFT already claimed."
        case .invalidRoyaltyAmount:
            return "Invalid royalty percentage."
        case .invalidSignature:
            return "Invalid signature detected."
        case .tokenNotClaimed:
            return "Token exists but has not been claimed yet."
        case .unknown(let code):
            return "Contract error (code \(code))."
        }
    }

    /// Get the numeric error code for this error
    var code: UInt32 {
        switch self {
        case .nonExistentToken: return 200
        case .incorrectOwner: return 201
        case .mathOverflow: return 205
        case .tokenIDsAreDepleted: return 206
        case .invalidAmount: return 207
        case .tokenAlreadyMinted: return 210
        case .invalidRoyaltyAmount: return 212
        case .invalidSignature: return 214
        case .tokenNotClaimed: return 215
        case .unknown(let code): return code
        }
    }

    /// Create ContractError from numeric error code
    static func fromCode(_ code: UInt32) -> ContractError {
        switch code {
        case 200: return .nonExistentToken
        case 201: return .incorrectOwner
        case 205: return .mathOverflow
        case 206: return .tokenIDsAreDepleted
        case 207: return .invalidAmount
        case 210: return .tokenAlreadyMinted
        case 212: return .invalidRoyaltyAmount
        case 214: return .invalidSignature
        case 215: return .tokenNotClaimed
        default: return .unknown(code: code)
        }
    }

    /// Extract contract error from error string representation
    static func fromErrorString(_ errorString: String) -> ContractError? {
        // Direct error code matches
        if errorString.contains("200") || errorString.contains("NonExistentToken") {
            return .nonExistentToken
        }
        if errorString.contains("201") || errorString.contains("IncorrectOwner") {
            return .incorrectOwner
        }
        if errorString.contains("205") || errorString.contains("MathOverflow") {
            return .mathOverflow
        }
        if errorString.contains("206") || errorString.contains("TokenIDsAreDepleted") {
            return .tokenIDsAreDepleted
        }
        if errorString.contains("207") || errorString.contains("InvalidAmount") {
            return .invalidAmount
        }
        if errorString.contains("210") ||
           errorString.contains("TokenAlreadyMinted") ||
           (errorString.contains("already") && errorString.contains("minted")) {
            return .tokenAlreadyMinted
        }
        if errorString.contains("212") || errorString.contains("InvalidRoyaltyAmount") {
            return .invalidRoyaltyAmount
        }
        if errorString.contains("214") || errorString.contains("InvalidSignature") {
            return .invalidSignature
        }
        if errorString.contains("215") || errorString.contains("TokenNotClaimed") {
            return .tokenNotClaimed
        }

        // Try to extract numeric error code using regex patterns
        let pattern1 = #"Error\(Contract,\s*#(\d+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern1, options: []),
           let match = regex.firstMatch(in: errorString, options: [], range: NSRange(location: 0, length: errorString.utf16.count)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: errorString),
           let code = UInt32(errorString[range]) {
            return ContractError.fromCode(code)
        }

        // Try a simpler pattern for Error(Contract, #XXX)
        let pattern1b = #"Error\(Contract, #(\d+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern1b, options: []),
           let match = regex.firstMatch(in: errorString, options: [], range: NSRange(location: 0, length: errorString.utf16.count)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: errorString),
           let code = UInt32(errorString[range]) {
            return ContractError.fromCode(code)
        }

        // Pattern 2: Look for standalone numbers that could be error codes
        let pattern2 = #"(?<!\d)(\d{3})(?!\d)"#
        if let regex = try? NSRegularExpression(pattern: pattern2, options: []),
           let match = regex.firstMatch(in: errorString, options: [], range: NSRange(location: 0, length: errorString.utf16.count)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: errorString),
           let code = UInt32(errorString[range]),
           code >= 200 && code <= 220 {
            return ContractError.fromCode(code)
        }

        // Pattern 3: Look for the specific format in diagnostic data: [\"failing with contract error\", 215]
        let pattern3 = #"\["failing with contract error", (\d+)\]"#
        if let regex = try? NSRegularExpression(pattern: pattern3, options: []),
           let match = regex.firstMatch(in: errorString, options: [], range: NSRange(location: 0, length: errorString.utf16.count)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: errorString),
           let code = UInt32(errorString[range]) {
            return ContractError.fromCode(code)
        }

        return nil
    }

}

// MARK: - NFC Errors

enum NFCError: LocalizedError {
    /// NFC is not available on this device
    case notAvailable

    /// NFC session was interrupted
    case sessionInterrupted

    /// Failed to connect to NFC tag
    case connectionFailed

    /// NFC tag read/write failed
    case readWriteFailed(String)

    /// Invalid NFC tag format
    case invalidTag

    /// NFC chip communication error
    case chipError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC is not available on this device."
        case .sessionInterrupted:
            return "NFC session interrupted."
        case .connectionFailed:
            return "NFC connection failed."
        case .readWriteFailed(let message):
            return "NFC read/write failed: \(message)"
        case .invalidTag:
            return "Invalid NFC tag format."
        case .chipError(let message):
            return "NFC chip error: \(message)"
        }
    }
}

// MARK: - Wallet Errors

enum WalletError: LocalizedError {
    /// No wallet is configured
    case noWallet

    /// Invalid wallet configuration
    case invalidWallet

    /// Failed to load private key
    case keyLoadFailed

    /// Invalid private key format
    case invalidKey

    /// Failed to sign transaction
    case signingFailed(String)

    /// Insufficient funds for transaction
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet configured."
        case .invalidWallet:
            return "Invalid wallet configuration."
        case .keyLoadFailed:
            return "Failed to load private key."
        case .invalidKey:
            return "Invalid private key format."
        case .signingFailed(let message):
            return "Failed to sign transaction: \(message)"
        case .insufficientFunds:
            return "Insufficient funds. Add XLM to account."
        }
    }
}

// MARK: - IPFS Errors

enum IPFSError: LocalizedError {
    /// Failed to download from IPFS
    case downloadFailed(String)

    /// Invalid IPFS hash or URL
    case invalidHash

    /// IPFS service unavailable
    case serviceUnavailable

    /// Failed to parse IPFS metadata
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Failed to download from IPFS: \(message)"
        case .invalidHash:
            return "Invalid IPFS hash or URL format."
        case .serviceUnavailable:
            return "IPFS service unavailable."
        case .parseFailed(let message):
            return "Failed to parse IPFS data: \(message)"
        }
    }
}

// MARK: - Secure Storage Errors

enum SecureKeyStorageError: LocalizedError {
    /// Failed to store data securely
    case storageFailed(String)

    /// Failed to retrieve data from secure storage
    case retrievalFailed(String)

    /// Failed to delete data from secure storage
    case deletionFailed(String)

    /// Data not found in secure storage
    case dataNotFound

    /// Secure storage is unavailable
    case unavailable

    /// Authentication required for secure storage access
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .storageFailed(let message):
            return "Failed to securely store data: \(message)"
        case .retrievalFailed(let message):
            return "Failed to retrieve data from secure storage: \(message)"
        case .deletionFailed(let message):
            return "Failed to delete data from secure storage: \(message)"
        case .dataNotFound:
            return "Required data not found in secure storage."
        case .unavailable:
            return "Secure storage unavailable."
        case .authenticationRequired:
            return "Authentication required."
        }
    }
}

// MARK: - Crypto Errors

enum CryptoError: LocalizedError {
    /// Invalid cryptographic operation
    case invalidOperation(String)

    /// Failed to generate signature
    case signatureFailed(String)

    /// Invalid signature format
    case invalidSignature

    /// Failed to verify signature
    case verificationFailed

    /// Invalid cryptographic key
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
        case .invalidOperation(let message):
            return "Invalid cryptographic operation: \(message)"
        case .signatureFailed(let message):
            return "Failed to generate signature: \(message)"
        case .invalidSignature:
            return "Invalid signature format."
        case .verificationFailed:
            return "Signature verification failed."
        case .invalidKey(let message):
            return "Invalid cryptographic key: \(message)"
        }
    }
}

// MARK: - DER Signature Parser Errors

enum DERSignatureParserError: LocalizedError {
    /// Invalid DER format
    case invalidFormat

    /// Failed to parse DER signature
    case parseFailed(String)

    /// Invalid signature components
    case invalidComponents

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid DER signature format."
        case .parseFailed(let message):
            return "Failed to parse DER signature: \(message)"
        case .invalidComponents:
            return "Invalid DER signature components."
        }
    }
}

// MARK: - NFT Errors

enum NFTError: LocalizedError {
    /// No wallet configured for NFT operations
    case noWallet

    /// Invalid token ID format
    case invalidTokenId

    /// Failed to download NFT data
    case downloadFailed(String)

    /// NFT metadata parsing failed
    case parseFailed(String)

    /// Image download failed
    case imageDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet available."
        case .invalidTokenId:
            return "Invalid token ID format."
        case .downloadFailed(let message):
            return "Failed to download NFT data: \(message)"
        case .parseFailed(let message):
            return "Failed to parse NFT metadata: \(message)"
        case .imageDownloadFailed(let message):
            return "Failed to download NFT image: \(message)"
        }
    }
}
