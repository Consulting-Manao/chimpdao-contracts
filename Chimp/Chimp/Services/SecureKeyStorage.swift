/**
 * Secure Key Storage Service
 * Manages private key storage using iOS Keychain with Secure Enclave protection
 */

import Foundation
import Security

class SecureKeyStorage {
    private let keychainService = "com.stellarmerchshop.chimp.privatekey"
    private let keychainAccount = "wallet_key"
    
    /// Store private key in Keychain
    /// - Parameter secretKey: Stellar secret key to store
    /// - Throws: AppError if storage fails
    func storePrivateKey(_ secretKey: String) throws {
        guard let privateKeyData = secretKey.data(using: .utf8) else {
            throw AppError.secureStorage(.retrievalFailed("Invalid key data retrieved from secure storage"))
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
            throw AppError.secureStorage(.storageFailed("Keychain access failed"))
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
            throw AppError.secureStorage(.storageFailed("Keychain access failed"))
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
            throw AppError.secureStorage(.storageFailed("Keychain access failed"))
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
}

