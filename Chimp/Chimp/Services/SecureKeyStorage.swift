/**
 * Secure Key Storage Service
 * Manages private key storage using iOS Keychain with Secure Enclave protection
 */

import Foundation
import Security

final class SecureKeyStorage {
    private let keychainService = "com.stellarmerchshop.chimp.privatekey"
    private let keychainAccount = "wallet_key"
    
    /// Store private key in Keychain
    /// - Parameter secretKey: Stellar secret key to store
    /// - Throws: AppError if storage fails
    func storePrivateKey(_ secretKey: String) throws {
        guard let privateKeyData = secretKey.data(using: .utf8) else {
            throw AppError.secureStorage(.storageFailed("Invalid key data format"))
        }
        
        // Delete existing key if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errorMessage = keychainErrorMessage(for: status)
            throw AppError.secureStorage(.storageFailed(errorMessage))
        }
    }
    
    /// Load private key from Keychain
    /// - Returns: Stellar secret key if found, nil otherwise
    /// - Throws: AppError if retrieval fails
    func loadPrivateKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let secretKey = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                return nil
            }
            let errorMessage = keychainErrorMessage(for: status)
            throw AppError.secureStorage(.retrievalFailed(errorMessage))
        }
        
        return secretKey
    }
    
    /// Delete stored private key
    /// - Throws: AppError if deletion fails
    func deletePrivateKey() throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(deleteQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let errorMessage = keychainErrorMessage(for: status)
            throw AppError.secureStorage(.deletionFailed(errorMessage))
        }
    }
    
    /// Check if a private key is stored
    /// - Returns: true if key exists, false otherwise
    func hasStoredKey() -> Bool {
        do {
            return try loadPrivateKey() != nil
        } catch {
            return false
        }
    }
    
    /// Get user-friendly error message for keychain status code
    /// - Parameter status: Keychain status code
    /// - Returns: Human-readable error message
    private func keychainErrorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Operation succeeded"
        case errSecItemNotFound:
            return "Item not found in keychain"
        case errSecDuplicateItem:
            return "Item already exists in keychain"
        case errSecAuthFailed:
            return "Authentication failed - device may be locked"
        case errSecInteractionNotAllowed:
            return "Interaction not allowed - device may be locked"
        case errSecNotAvailable:
            return "Keychain services are not available"
        case errSecReadOnly:
            return "Keychain is read-only"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failed"
        case errSecDecode:
            return "Unable to decode the provided data"
        case errSecUnimplemented:
            return "Function or operation not implemented"
        default:
            return "Keychain error: \(status)"
        }
    }
}

