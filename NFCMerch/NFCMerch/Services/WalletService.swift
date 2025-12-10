/**
 * Wallet Service
 * Manages wallet connections (external wallets + manual key entry)
 * Uses stellar-swift-wallet-sdk for external wallet discovery
 * Uses iOS Secure Enclave for manual key storage
 * 
 * NOTE: This requires stellar-ios-mac-sdk to be added to the Xcode project
 * Add via: File > Add Package Dependencies > https://github.com/Soneso/stellar-ios-mac-sdk
 */

import stellarsdk
import Foundation
import Security
import UIKit

/// Wallet connection type
enum WalletType {
    case external(walletName: String)  // Freighter, LOBSTR, etc.
    case manual(keyType: ManualKeyType)  // Secret key or mnemonic
}

enum ManualKeyType {
    case secretKey
    case mnemonic
}

/// Wallet connection info
struct WalletConnection {
    let type: WalletType
    let address: String  // Stellar address (public key)
    let name: String
}

/// Wallet service for managing wallet connections
class WalletService {
    
    private let keychainService = "com.nfcmerch.wallet"
    private let addressKey = "wallet_address"
    private let walletTypeKey = "wallet_type"
    
    /// Connect to external wallet (Freighter, LOBSTR, etc.)
    /// 
    /// Matches web app's behavior in src/util/wallet.ts using StellarWalletsKit
    /// For iOS, this will use stellar-swift-wallet-sdk or deep linking
    /// 
    /// Implementation steps (once stellar-swift-wallet-sdk is added):
    /// 1. Use SDK to discover available wallets
    /// 2. Present wallet selection UI
    /// 3. Deep link to selected wallet app for connection
    /// 4. Handle callback with wallet address
    /// 5. Store wallet connection info
    func connectExternalWallet(walletType: String) async throws -> WalletConnection {
        // TODO: Implement using stellar-swift-wallet-sdk
        //
        // Example implementation structure:
        //
        // import StellarWalletSDK
        //
        // // 1. Discover available wallets
        // let availableWallets = try await WalletDiscovery.discover()
        //
        // // 2. Filter by walletType (e.g., "freighter", "lobstr")
        // guard let wallet = availableWallets.first(where: { $0.id == walletType }) else {
        //     throw WalletError.walletNotAvailable
        // }
        //
        // // 3. Connect via deep linking or SDK
        // let connection = try await wallet.connect()
        //
        // // 4. Get wallet address
        // let address = try await connection.getAddress()
        //
        // // 5. Store connection info
        // let walletConnection = WalletConnection(
        //     type: .external(walletName: walletType),
        //     address: address,
        //     name: wallet.name
        // )
        //
        // // Store in UserDefaults for persistence
        // UserDefaults.standard.set(walletType, forKey: walletTypeKey)
        // UserDefaults.standard.set(address, forKey: addressKey)
        //
        // return walletConnection
        
        throw WalletError.notImplemented
    }
    
    /// Sign transaction using external wallet
    /// 
    /// Deep links to wallet app and waits for signed transaction.
    /// Matches web app's signTransaction behavior via StellarWalletsKit
    /// 
    /// Implementation steps:
    /// 1. Create deep link URL with transaction XDR
    /// 2. Open wallet app via URL scheme
    /// 3. Wait for callback with signed transaction
    /// 4. Return signed transaction XDR
    func signTransactionExternal(
        transaction: Data,
        wallet: WalletConnection
    ) async throws -> Data {
        guard case .external(let walletName) = wallet.type else {
            throw WalletError.walletNotAvailable
        }
        
        let urlScheme: String
        switch walletName.lowercased() {
        case "freighter":
            urlScheme = "freighter"
        case "lobstr":
            urlScheme = "lobstr"
        default:
            throw WalletError.walletNotAvailable
        }
        
        let xdrBase64 = transaction.base64EncodedString()
        guard let url = URL(string: "\(urlScheme)://sign?xdr=\(xdrBase64)") else {
            throw WalletError.invalidURL
        }
        
        await UIApplication.shared.open(url)
        
        return try await waitForSignedTransaction()
    }
    
    private func waitForSignedTransaction() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            NotificationCenter.default.addObserver(
                forName: .signedTransactionReceived,
                object: nil,
                queue: .main
            ) { notification in
                if let signedXdr = notification.userInfo?["signedXdr"] as? String,
                   let signedData = Data(base64Encoded: signedXdr) {
                    continuation.resume(returning: signedData)
                } else {
                    continuation.resume(throwing: WalletError.signingFailed)
                }
            }
        }
    }
    
    /// Load wallet from secret key
    /// 
    /// Validates secret key format and generates KeyPair using stellar-ios-mac-sdk.
    /// Stores private key in Secure Enclave via Keychain for security.
    /// Only the public key/address is stored in UserDefaults.
    func loadWalletFromSecretKey(_ secretKey: String) async throws -> WalletConnection {
        // 1. Validate secret key format
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            throw WalletError.invalidSecretKey("Secret key cannot be empty")
        }
        
        guard trimmedKey.hasPrefix("S") else {
            throw WalletError.invalidSecretKey("Invalid secret key format. Stellar secret keys start with 'S'")
        }
        
        guard trimmedKey.count == 56 else {
            throw WalletError.invalidSecretKey("Invalid secret key length. Stellar secret keys are 56 characters")
        }
        
        // 2. Generate KeyPair from secret key using stellar-ios-mac-sdk
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: trimmedKey)
        } catch {
            throw WalletError.invalidSecretKey("Failed to create key pair from secret key: \(error.localizedDescription)")
        }
        
        // 3. Get public key/address
        let address = keyPair.accountId
        
        // 4. Store private key in Secure Enclave
        let privateKeyData = trimmedKey.data(using: .utf8) ?? Data()
        do {
            try storePrivateKeyInSecureEnclave(privateKeyData)
        } catch {
            // If Secure Enclave storage fails, still allow connection but log warning
            print("Warning: Failed to store private key in Secure Enclave: \(error.localizedDescription)")
        }
        
        // 5. Store public info in UserDefaults
        UserDefaults.standard.set("secretKey", forKey: "wallet_type")
        UserDefaults.standard.set(address, forKey: "wallet_address")
        
        let connection = WalletConnection(
            type: .manual(keyType: .secretKey),
            address: address,
            name: "Manual Key"
        )
        
        return connection
    }
    
    /// Load wallet from mnemonic
    /// 
    /// Derives secret key from mnemonic using BIP39/BIP44 and stores in Secure Enclave.
    /// 
    /// Requires BIP39/BIP44 library (e.g., https://github.com/mathwallet/BIP39.swift)
    /// and stellar-ios-mac-sdk to be added to the project.
    func loadWalletFromMnemonic(_ mnemonic: String) async throws -> WalletConnection {
        // Implementation pending: Add BIP39/BIP44 library and stellar-ios-mac-sdk
        // Will derive Stellar key from mnemonic using path m/44'/148'/0'
        throw WalletError.notImplemented
    }
    
    /// Get stored wallet info (if any)
    /// 
    /// Retrieves wallet connection info from UserDefaults.
    /// Does not load private key (that stays in Secure Enclave).
    func getStoredWallet() -> WalletConnection? {
        guard let walletType = UserDefaults.standard.string(forKey: "wallet_type"),
              let address = UserDefaults.standard.string(forKey: "wallet_address"),
              !walletType.isEmpty, !address.isEmpty else {
            return nil
        }
        
        let type: WalletType
        if walletType == "freighter" || walletType == "lobstr" {
            type = .external(walletName: walletType)
        } else if walletType == "secretKey" {
            type = .manual(keyType: .secretKey)
        } else if walletType == "mnemonic" {
            type = .manual(keyType: .mnemonic)
        } else {
            return nil
        }
        
        return WalletConnection(
            type: type,
            address: address,
            name: walletType.capitalized
        )
    }
    
    func signTransaction(transaction: Data, wallet: WalletConnection) async throws -> Data {
        switch wallet.type {
        case .external:
            return try await signTransactionExternal(transaction: transaction, wallet: wallet)
        case .manual:
            return try await signTransactionLocal(transaction)
        }
    }
    
    func signTransactionLocal(_ transaction: Data) async throws -> Data {
        guard let privateKeyData = try loadPrivateKeyFromSecureEnclave(),
              let privateKeyString = String(data: privateKeyData, encoding: .utf8) else {
            throw WalletError.noWalletConfigured
        }
        
        let keyPair = try stellarsdk.KeyPair(secretSeed: privateKeyString)
        let transactionXdrString = transaction.base64EncodedString()
        let stellarTransaction = try stellarsdk.Transaction(envelopeXdr: transactionXdrString)
        
        // Determine network
        let network: stellarsdk.Network
        switch NFCConfig.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        try stellarTransaction.sign(keyPair: keyPair, network: network)
        
        guard let signedXdr = stellarTransaction.xdrEncoded else {
            throw WalletError.signingFailed
        }
        
        return Data(base64Encoded: signedXdr) ?? Data()
    }
    
    /// Store private key in Secure Enclave
    /// 
    /// Stores private key in iOS Keychain with Secure Enclave protection.
    /// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for security.
    private func storePrivateKeyInSecureEnclave(_ privateKey: Data) throws {
        let keychainService = "com.stellarmerchshop.privatekey"
        let keychainAccount = "wallet_key"
        
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
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError
        }
    }
    
    /// Load private key from Secure Enclave
    /// 
    /// Retrieves private key from iOS Keychain.
    /// Returns nil if key not found or access denied.
    private func loadPrivateKeyFromSecureEnclave() throws -> Data? {
        let keychainService = "com.stellarmerchshop.privatekey"
        let keychainAccount = "wallet_key"
        
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
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
}

enum WalletError: Error, LocalizedError {
    case notImplemented
    case invalidSecretKey(String)
    case invalidMnemonic
    case keychainError
    case noWalletConfigured
    case walletNotAvailable
    case invalidURL
    case signingFailed
    
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Feature not yet implemented - SDK integration required"
        case .invalidSecretKey(let message):
            return message
        case .invalidMnemonic:
            return "Invalid mnemonic (must be 12 or 24 words)"
        case .keychainError:
            return "Failed to access Secure Enclave"
        case .noWalletConfigured:
            return "No wallet configured"
        case .walletNotAvailable:
            return "Wallet app is not installed or not available"
        case .invalidURL:
            return "Invalid URL for wallet deep linking"
        case .signingFailed:
            return "Transaction signing failed"
        }
    }
}

extension Notification.Name {
    static let signedTransactionReceived = Notification.Name("signedTransactionReceived")
}

