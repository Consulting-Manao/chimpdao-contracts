/**
 * Secure Key Storage Service
 * Manages private key storage using iOS Keychain with biometric protection
 */

import Foundation
import Security
import LocalAuthentication

final class SecureKeyStorage {
    /// Provide access to the private key. Every access requires fresh biometric authentication.
    /// - Parameters:
    ///   - reason: The localized reason displayed in the Face ID prompt.
    ///   - work: Closure receiving the private key string. Must not store the key beyond the closure scope.
    /// - Returns: Generic value returned by the closure.
    /// - Throws: Rethrows errors from Keychain access or the closure.
    /// 
    /// Security Note: A fresh LAContext is created for each access, ensuring biometric authentication
    /// is always required. The defer block attempts to clear a Data buffer copy, but due to Swift's String
    /// copy-on-write semantics, the original `privateKey` String may still exist in memory with multiple
    /// copies after this method returns. Swift's automatic memory management will eventually reclaim this
    /// memory, but there is a brief window where the key material exists in unencrypted memory.
    /// This is a known limitation of Swift and affects all iOS applications similarly. The key is still
    /// protected by Keychain encryption at rest and biometric authentication required for access.
    func withPrivateKey<T>(reason: String = "Authenticate to access your wallet", work: (String) throws -> T) throws -> T {
        let context = LAContext()
        context.localizedReason = reason
        guard let privateKey = try loadPrivateKey(using: context) else {
            throw AppError.wallet(.noWallet)
        }
        // Attempt to clear memory after use (limited effectiveness due to Swift's String semantics)
        defer {
            // Overwrite temporary buffer copy - note that the original String may still exist
            // in memory due to Swift's copy-on-write semantics and closure capture
            var buffer = Data(privateKey.utf8)
            buffer.resetBytes(in: 0..<buffer.count)
        }
        return try work(privateKey)
    }

    // MARK: - Private helpers
    
    private func loadPrivateKey(using context: LAContext) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw AppError.secureStorage(.authenticationRequired)
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let secretKey = String(data: data, encoding: .utf8) else {
            throw AppError.secureStorage(.retrievalFailed(keychainErrorMessage(for: status)))
        }
        return secretKey
    }
    private let keychainService = "com.consulting-manao.chimp.privatekey"
    private let keychainAccount = "wallet_key"
    
    /// Store private key in Keychain with biometric protection
    /// - Parameter secretKey: Stellar secret key to store
    /// - Throws: AppError if storage fails
    func storePrivateKey(_ secretKey: String) throws {
        guard let privateKeyData = secretKey.data(using: .utf8) else {
            throw AppError.secureStorage(.storageFailed("Invalid key data format"))
        }
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            let errorMessage = error?.takeRetainedValue().localizedDescription ?? "Failed to create access control"
            throw AppError.secureStorage(.storageFailed(errorMessage))
        }
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessControl as String: accessControl
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            let errorMessage = keychainErrorMessage(for: status)
            throw AppError.secureStorage(.storageFailed(errorMessage))
        }
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
    
    func hasStoredKey() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseAuthenticationContext as String: context
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
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
            return "Authentication failed"
        case errSecUserCanceled:
            return "Authentication was canceled"
        case errSecInteractionNotAllowed:
            return "Authentication required"
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
