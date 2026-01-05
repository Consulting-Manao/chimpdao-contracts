/**
 * App Configuration
 * Manages network and contract configuration
 * Reads from build settings (Info.plist) for network and contract IDs
 */

import Foundation

enum AppNetwork: String {
    case testnet = "testnet"
    case mainnet = "mainnet"
}

final class AppConfig {
    static let shared = AppConfig()
    
    private let networkKey = "app_network" // UserDefaults key for runtime override
    private let contractIdKey = "app_contract_id" // UserDefaults key for runtime override
    private let adminModeKey = "app_admin_mode" // UserDefaults key for runtime override
    
    // Build configuration keys (set in Info.plist via build settings)
    private let buildNetworkKey = "STELLAR_NETWORK"
    private let buildContractIdTestnetKey = "STELLAR_CONTRACT_ID_TESTNET"
    private let buildContractIdMainnetKey = "STELLAR_CONTRACT_ID_MAINNET"
    private let buildAdminModeKey = "ADMIN_MODE"
    
    private init() {}
    
    /// Current network setting
    /// First checks UserDefaults (runtime override), then build configuration
    var currentNetwork: AppNetwork {
        get {
            // Check for runtime override in UserDefaults
            if let networkString = UserDefaults.standard.string(forKey: networkKey),
               let network = AppNetwork(rawValue: networkString) {
                return network
            }
            
            // Fall back to build configuration
            if let buildNetwork = Bundle.main.infoDictionary?[buildNetworkKey] as? String,
               let network = AppNetwork(rawValue: buildNetwork.lowercased()) {
                return network
            }
            
            return .testnet // Default to testnet
        }
        set {
            // Store in UserDefaults for runtime override
            UserDefaults.standard.set(newValue.rawValue, forKey: networkKey)
        }
    }
    
    /// Contract ID for current network
    /// First checks UserDefaults (runtime override), then build configuration
    var contractId: String {
        get {
            // Check for runtime override in UserDefaults
            if let overrideId = UserDefaults.standard.string(forKey: contractIdKey), !overrideId.isEmpty {
                return overrideId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Fall back to build configuration based on current network
            let buildKey = currentNetwork == .testnet ? buildContractIdTestnetKey : buildContractIdMainnetKey
            if let buildContractId = Bundle.main.infoDictionary?[buildKey] as? String, !buildContractId.isEmpty {
                return buildContractId.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            return "" // No contract ID configured
        }
        set {
            // Store in UserDefaults for runtime override
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: contractIdKey)
        }
    }
    
    /// Validates contract ID format
    /// Contract IDs should be 56 characters, start with 'C', and be valid base32
    func validateContractId(_ contractId: String) -> Bool {
        // Stellar contract IDs are 56 characters, start with 'C'
        guard contractId.count == 56,
              contractId.hasPrefix("C") else {
            return false
        }

        // Check if it's valid base32 (alphanumeric, no ambiguous characters)
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return contractId.uppercased().unicodeScalars.allSatisfy { validChars.contains($0) }
    }

    /// Validates Stellar address format
    /// Stellar addresses should be 56 characters, start with 'G', and be valid base32
    func validateStellarAddress(_ address: String) -> Bool {
        // Stellar addresses are 56 characters, start with 'G'
        guard address.count == 56,
              address.hasPrefix("G") else {
            return false
        }

        // Check if it's valid base32 (alphanumeric, no ambiguous characters)
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        return address.uppercased().unicodeScalars.allSatisfy { validChars.contains($0) }
    }
    
    /// RPC URL based on current network
    var rpcUrl: String {
        switch currentNetwork {
        case .testnet:
            return "https://soroban-testnet.stellar.org"
        case .mainnet:
            return "https://rpc.lightsail.network"
        }
    }
    
    /// Horizon URL based on current network
    var horizonUrl: String {
        switch currentNetwork {
        case .testnet:
            return "https://horizon-testnet.stellar.org"
        case .mainnet:
            return "https://horizon.stellar.org"
        }
    }
    
    /// Network passphrase based on current network
    var networkPassphrase: String {
        switch currentNetwork {
        case .testnet:
            return "Test SDF Network ; September 2015"
        case .mainnet:
            return "Public Global Stellar Network ; September 2015"
        }
    }
    
    /// Get contract ID from build configuration (without UserDefaults override)
    func getBuildConfigContractId() -> String {
        let buildKey = currentNetwork == .testnet ? buildContractIdTestnetKey : buildContractIdMainnetKey
        if let buildContractId = Bundle.main.infoDictionary?[buildKey] as? String, !buildContractId.isEmpty {
            return buildContractId
        }
        return ""
    }
    
    /// Get network from build configuration (without UserDefaults override)
    func getBuildConfigNetwork() -> AppNetwork? {
        if let buildNetwork = Bundle.main.infoDictionary?[buildNetworkKey] as? String,
           let network = AppNetwork(rawValue: buildNetwork.lowercased()) {
            return network
        }
        return nil
    }
    
    /// Admin mode flag - set via build configuration
    /// First checks UserDefaults (runtime override), then build configuration
    var isAdminMode: Bool {
        get {
            // Check for runtime override in UserDefaults
            if UserDefaults.standard.object(forKey: adminModeKey) != nil {
                return UserDefaults.standard.bool(forKey: adminModeKey)
            }
            
            // Fall back to build configuration
            if let buildAdminMode = Bundle.main.infoDictionary?[buildAdminModeKey] as? String {
                let lowercased = buildAdminMode.lowercased()
                return lowercased == "true" || lowercased == "1" || lowercased == "yes"
            }
            
            return false // Default to regular user mode
        }
        set {
            // Store in UserDefaults for runtime override
            UserDefaults.standard.set(newValue, forKey: adminModeKey)
        }
    }
}
