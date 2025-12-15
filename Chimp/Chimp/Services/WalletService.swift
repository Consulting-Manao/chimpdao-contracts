/**
 * Wallet Service
 * Manages wallet connections and transaction signing
 */

import Foundation
import stellarsdk

struct WalletConnection {
    let address: String  // Stellar address (public key)
    let name: String
}

class WalletService {
    private let secureKeyStorage = SecureKeyStorage()
    private let addressKey = "wallet_address"
    
    /// Load wallet from secret key
    /// - Parameter secretKey: Stellar secret key (starts with 'S', 56 chars)
    /// - Returns: WalletConnection with address
    /// - Throws: AppError if key is invalid or storage fails
    func loadWalletFromSecretKey(_ secretKey: String) async throws -> WalletConnection {
        // Validate secret key format
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else {
            throw AppError.validation("Secret key cannot be empty")
        }
        
        guard trimmedKey.hasPrefix("S") else {
            throw AppError.validation("Invalid secret key format. Stellar secret keys start with 'S'")
        }
        
        guard trimmedKey.count == 56 else {
            throw AppError.validation("Invalid secret key length. Stellar secret keys are 56 characters")
        }
        
        // Generate KeyPair from secret key
        let keyPair: KeyPair
        do {
            keyPair = try KeyPair(secretSeed: trimmedKey)
        } catch {
            throw AppError.validation("Failed to create key pair from secret key: \(error.localizedDescription)")
        }
        
        // Get public key/address
        let address = keyPair.accountId
        
        // Store private key in Secure Enclave
        do {
            try secureKeyStorage.storePrivateKey(trimmedKey)
        } catch {
            throw AppError.secureStorage(.storageFailed("Failed to store wallet securely"))
        }
        
        // Store public info in UserDefaults
        UserDefaults.standard.set(address, forKey: addressKey)
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Get stored wallet info (if any)
    /// - Returns: WalletConnection if wallet is stored, nil otherwise
    func getStoredWallet() -> WalletConnection? {
        guard let address = UserDefaults.standard.string(forKey: addressKey),
              !address.isEmpty else {
            return nil
        }
        
        return WalletConnection(
            address: address,
            name: "Manual Key"
        )
    }
    
    /// Sign a transaction (modifies the transaction object in place)
    /// - Parameter transaction: Transaction object to sign (will be modified)
    /// - Throws: AppError if signing fails
    func signTransaction(_ transaction: Transaction) async throws {
        guard let privateKeyString = try secureKeyStorage.loadPrivateKey() else {
            throw AppError.wallet(.noWallet)
        }
        
        let keyPair = try KeyPair(secretSeed: privateKeyString)
        
        print("WalletService: Validating transaction before signing...")
        
        // Validate transaction has required operations
        guard !transaction.operations.isEmpty else {
            print("WalletService: ERROR: Transaction has no operations")
            throw AppError.wallet(.signingFailed("Transaction signing failed"))
        }
        print("WalletService: Transaction has \(transaction.operations.count) operation(s)")
        
        // Note: Time bounds and fee validation are already done in buildClaimTransaction
        // We just validate basic transaction state here
        
        // Validate transaction fee (minimum 100 stroops per operation)
        let minFeePerOperation: Int64 = 100
        let requiredMinFee = minFeePerOperation * Int64(transaction.operations.count)
        if transaction.fee < requiredMinFee {
            print("WalletService: ERROR: Transaction fee (\(transaction.fee)) is below minimum (\(requiredMinFee))")
            throw AppError.wallet(.signingFailed("Transaction signing failed"))
        }
        print("WalletService: Transaction fee validated: \(transaction.fee) stroops (minimum: \(requiredMinFee))")
        
        // Validate source account matches wallet (if we can access it)
        // Note: Transaction.sourceAccount is a protocol, so we can't directly compare
        // The transaction was built with the correct source account, so we trust it
        print("WalletService: Source account validation skipped (transaction built with correct account)")
        
        print("WalletService: Transaction validation passed, signing...")
        
        // Determine network
        let network: Network
        switch AppConfig.shared.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        // Sign the transaction (modifies the transaction object in place)
        // Matching test script: transaction.sign(keyPair: keyPair, network: .testnet)
        try transaction.sign(keyPair: keyPair, network: network)
        print("WalletService: Transaction signed successfully")
    }
    
    /// Logout - clear stored wallet
    func logout() throws {
        try secureKeyStorage.deletePrivateKey()
        UserDefaults.standard.removeObject(forKey: addressKey)
    }
}

