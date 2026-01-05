import Foundation
import stellarsdk

/// Shared utilities for blockchain operations
final class BlockchainHelpers {
    private static let config = AppConfig.shared
    
    /// Convert AppNetwork to stellarsdk Network
    /// - Returns: Network enum value
    static func getNetwork() -> Network {
        switch config.currentNetwork {
        case .testnet:
            return .testnet
        case .mainnet:
            return .public
        }
    }
    
    /// Create ClientOptions for contract calls
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - sourceKeyPair: Source account keypair
    /// - Returns: ClientOptions instance
    /// - Throws: AppError if contract ID is invalid
    static func createClientOptions(contractId: String, sourceKeyPair: KeyPair) throws -> ClientOptions {
        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        return ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: getNetwork(),
            rpcUrl: config.rpcUrl
        )
    }
    
    /// Validate contract ID format
    /// - Parameter contractId: Contract ID to validate
    /// - Returns: true if valid, false otherwise
    static func validateContractId(_ contractId: String) -> Bool {
        return config.validateContractId(contractId)
    }
    
    /// Check if error is a contract error and convert it
    /// - Parameter error: Error to check
    /// - Returns: AppError with contract error if applicable, nil otherwise
    static func extractContractError(from error: Error) -> AppError? {
        let errorString = "\(error)"
        if let contractError = ContractError.fromErrorString(errorString) {
            return AppError.blockchain(.contract(contractError))
        }
        return nil
    }
    
    /// Simulate transaction and decode XDR result
    /// - Parameters:
    ///   - transaction: Transaction to simulate
    ///   - rpcClient: SorobanServer instance
    /// - Returns: Decoded SCValXDR result
    /// - Throws: AppError if simulation or decoding fails
    static func simulateAndDecode(transaction: Transaction, rpcClient: SorobanServer) async throws -> SCValXDR {
        let simulateRequest = SimulateTransactionRequest(transaction: transaction)
        let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)
        
        switch simulateResponse {
        case .success(let simulateResult):
            guard let xdrString = simulateResult.results?.first?.xdr else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            guard let xdrData = Data(base64Encoded: xdrString) else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            let returnValue: SCValXDR
            do {
                returnValue = try XDRDecoder.decode(SCValXDR.self, data: xdrData)
            } catch {
                Logger.logError("Failed to decode XDR result", error: error, category: .blockchain)
                throw AppError.blockchain(.invalidResponse)
            }
            
            return returnValue
        case .failure(let error):
            // Check if it's a contract error
            if let contractError = extractContractError(from: error) {
                throw contractError
            }
            throw AppError.blockchain(.invalidResponse)
        }
    }
    
    /// Build and simulate a contract call transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - method: Method name to call
    ///   - arguments: Method arguments
    ///   - sourceKeyPair: Source account keypair
    ///   - rpcClient: SorobanServer instance
    /// - Returns: Tuple of (AssembledTransaction, SCValXDR result)
    /// - Throws: AppError if building or simulation fails
    static func buildAndSimulate(
        contractId: String,
        method: String,
        arguments: [SCValXDR],
        sourceKeyPair: KeyPair,
        rpcClient: SorobanServer
    ) async throws -> (AssembledTransaction, SCValXDR) {
        let clientOptions = try createClientOptions(contractId: contractId, sourceKeyPair: sourceKeyPair)
        
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: method,
            arguments: arguments
        )
        
        let assembledTx: AssembledTransaction
        do {
            assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        } catch {
            // Check if it's a contract error
            if let contractError = extractContractError(from: error) {
                throw contractError
            }
            throw AppError.blockchain(.invalidResponse)
        }
        
        guard let rawTx = assembledTx.raw else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        let returnValue = try await simulateAndDecode(transaction: rawTx, rpcClient: rpcClient)
        
        return (assembledTx, returnValue)
    }
    
    /// Build a transaction without simulating (for write operations)
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - method: Method name to call
    ///   - arguments: Method arguments
    ///   - sourceKeyPair: Source account keypair
    /// - Returns: Transaction object ready for signing
    /// - Throws: AppError if building fails
    static func buildTransaction(
        contractId: String,
        method: String,
        arguments: [SCValXDR],
        sourceKeyPair: KeyPair
    ) async throws -> Transaction {
        let clientOptions = try createClientOptions(contractId: contractId, sourceKeyPair: sourceKeyPair)
        
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: method,
            arguments: arguments
        )
        
        let assembledTx: AssembledTransaction
        do {
            assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        } catch {
            // Check if it's a contract error
            if let contractError = extractContractError(from: error) {
                throw contractError
            }
            throw AppError.blockchain(.invalidResponse)
        }
        
        guard let rawTx = assembledTx.raw else {
            throw AppError.blockchain(.transactionFailed)
        }
        
        return rawTx
    }
    
    /// Get transaction hash for a transaction
    /// - Parameter transaction: Transaction to hash
    /// - Returns: Transaction hash string
    /// - Throws: AppError if hashing fails
    static func getTransactionHash(_ transaction: Transaction) throws -> String {
        let network = getNetwork()
        return try transaction.getTransactionHash(network: network)
    }
}

