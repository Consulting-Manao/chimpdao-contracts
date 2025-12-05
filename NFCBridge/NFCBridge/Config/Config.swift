/**
 * Configuration Constants
 * Network and contract configuration for testnet
 */

import Foundation

struct NFCConfig {
    /// Recovery ID for Infineon SECORA chips (hardcoded to 1)
    static let recoveryId: UInt8 = 1
    
    /// Network configuration
    enum Network {
        case testnet
        case mainnet
        case futurenet
        
        var passphrase: String {
            switch self {
            case .testnet:
                return "Test SDF Network ; September 2015"
            case .mainnet:
                return "Public Global Stellar Network ; September 2015"
            case .futurenet:
                return "Test SDF Future Network ; October 2022"
            }
        }
        
        var horizonUrl: String {
            switch self {
            case .testnet:
                return "https://horizon-testnet.stellar.org"
            case .mainnet:
                return "https://horizon.stellar.org"
            case .futurenet:
                return "https://horizon-futurenet.stellar.org"
            }
        }
        
        var rpcUrl: String {
            switch self {
            case .testnet:
                return "https://soroban-testnet.stellar.org"
            case .mainnet:
                return "https://soroban-rpc.mainnet.stellar.org"
            case .futurenet:
                return "https://rpc-futurenet.stellar.org"
            }
        }
    }
    
    /// Current network (default: testnet)
    static var currentNetwork: Network = .testnet
    
    /// Network passphrase
    static var networkPassphrase: String {
        return currentNetwork.passphrase
    }
    
    /// Horizon URL
    static var horizonUrl: String {
        return currentNetwork.horizonUrl
    }
    
    /// RPC URL
    static var rpcUrl: String {
        return currentNetwork.rpcUrl
    }
    
    /// Contract ID - configure this for your deployed contract
    /// Set via UserDefaults or environment variable
    static var contractId: String {
        // Check UserDefaults first (allows runtime override)
        if let stored = UserDefaults.standard.string(forKey: "contract_id"), !stored.isEmpty {
            return stored
        }
        
        // Default contract ID for testnet
        return "CD5GYISJJKTE5SMZHS4UVSBXM2A2DKUUOUHAK2SZ24IU5TOBRV54CPK3"
    }
    
    /// Set contract ID
    static func setContractId(_ id: String) {
        UserDefaults.standard.set(id, forKey: "contract_id")
    }
}

