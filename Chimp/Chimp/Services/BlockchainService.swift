/**
 * Blockchain Service
 * Handles Soroban contract interactions
 */

import Foundation
import stellarsdk
import OSLog

final class BlockchainService {
    private let config = AppConfig.shared

    /// RPC client instance that gets recreated when network changes
    private var rpcClient: SorobanServer
    
    init() {
        self.rpcClient = SorobanServer(endpoint: config.rpcUrl)
        
        // Observe network changes and recreate RPC client
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNetworkChange),
            name: .networkDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleNetworkChange() {
        self.rpcClient = SorobanServer(endpoint: config.rpcUrl)
        Logger.logDebug("RPC client recreated for network: \(config.currentNetwork.rawValue)", category: .blockchain)
    }
    
    /// Get owner of a token from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - tokenId: Token ID
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Owner address string
    /// - Throws: AppError if call fails
    func getTokenOwner(contractId: String, tokenId: UInt64, sourceKeyPair: KeyPair) async throws -> String {
        let args: [SCValXDR] = [SCValXDR.u64(tokenId)]
        
        let (_, returnValue) = try await BlockchainHelpers.buildAndSimulate(
            contractId: contractId,
            method: "owner_of",
            arguments: args,
            sourceKeyPair: sourceKeyPair,
            rpcClient: rpcClient
        )
        
        guard case .address(let address) = returnValue else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        guard let ownerAddress = address.accountId else {
            throw AppError.blockchain(.invalidResponse)
        }
        
        return ownerAddress
    }

    /// Get token ID for a given chip public key from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Chip's public key (65 bytes, uncompressed SEC1 format)
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Token ID
    /// - Throws: AppError if call fails
    func getTokenId(contractId: String, publicKey: Data, sourceKeyPair: KeyPair) async throws -> UInt64 {
        guard publicKey.count == 65 else {
            throw AppError.validation("Invalid public key length: \(publicKey.count), expected 65")
        }
        
        let args: [SCValXDR] = [SCValXDR.bytes(publicKey)]
        
        do {
            let (_, returnValue) = try await BlockchainHelpers.buildAndSimulate(
                contractId: contractId,
                method: "token_id",
                arguments: args,
                sourceKeyPair: sourceKeyPair,
                rpcClient: rpcClient
            )
            
            guard case .u64(let tokenId) = returnValue else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            return tokenId
        } catch {
            // Check for account not found errors
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("could not find account") || 
               errorLowercased.contains("account not found") ||
               errorLowercased.contains("does not exist") {
                throw AppError.wallet(.noWallet)
            }
            
            // Re-throw if already AppError
            if error is AppError {
                throw error
            }
            
            // Check for contract errors
            if let contractError = BlockchainHelpers.extractContractError(from: error) {
                throw contractError
            }
            
            throw AppError.blockchain(.transactionRejected(errorString))
        }
    }

    /// Get token URI for a given token ID from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - tokenId: Token ID
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Token URI string (IPFS URL)
    /// - Throws: AppError if call fails
    func getTokenUri(contractId: String, tokenId: UInt64, sourceKeyPair: KeyPair) async throws -> String {
        let args: [SCValXDR] = [SCValXDR.u64(tokenId)]
        
        let (_, returnValue) = try await BlockchainHelpers.buildAndSimulate(
            contractId: contractId,
            method: "token_uri",
            arguments: args,
            sourceKeyPair: sourceKeyPair,
            rpcClient: rpcClient
        )
        
        let uri: String
        switch returnValue {
        case .string(let stringValue):
            uri = stringValue
        case .bytes(let bytesValue):
            guard let stringFromBytes = String(data: Data(bytesValue), encoding: .utf8) else {
                throw AppError.blockchain(.invalidResponse)
            }
            uri = stringFromBytes
        default:
            throw AppError.blockchain(.invalidResponse)
        }
        
        // Clean up the URI - remove quotes and null bytes
        var cleanedUri = uri.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        cleanedUri = cleanedUri.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        
        return cleanedUri
    }

    /// Get nonce for a public key from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Public key as Data (65 bytes, uncompressed)
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Current nonce value
    /// - Throws: AppError if call fails (throws instead of returning 0)
    func getNonce(contractId: String, publicKey: Data, sourceKeyPair: KeyPair) async throws -> UInt32 {
        let args: [SCValXDR] = [SCValXDR.bytes(publicKey)]
        
        do {
            let (_, returnValue) = try await BlockchainHelpers.buildAndSimulate(
                contractId: contractId,
                method: "get_nonce",
                arguments: args,
                sourceKeyPair: sourceKeyPair,
                rpcClient: rpcClient
            )
            
            guard case .u32(let nonce) = returnValue else {
                throw AppError.blockchain(.invalidResponse)
            }
            
            return nonce
        } catch {
            // Re-throw if already AppError
            if error is AppError {
                throw error
            }
            
            // Check for contract errors
            if let contractError = BlockchainHelpers.extractContractError(from: error) {
                throw contractError
            }
            
            // For nonce, if it's a "not found" type error, return 0 (first use)
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("not found") || 
               errorLowercased.contains("does not exist") ||
               errorLowercased.contains("no data") {
                return 0
            }
            
            throw AppError.blockchain(.invalidResponse)
        }
    }
    
    /// Determine recovery ID by simulating the claim call with each recovery ID (0-3)
    /// This is done offline (simulation only, no transaction submission)
    /// Matches JS implementation: determineRecoveryId() in src/util/crypto.ts
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - claimant: Claimant address
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair
    /// - Returns: The correct recovery ID (0-3)
    /// - Throws: AppError if no matching recovery ID found
    func determineRecoveryId(
        contractId: String,
        claimant: String,
        message: Data,
        signature: Data,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> UInt32 {
        Logger.logDebug("determineRecoveryId called (offline, using contract simulation)", category: .blockchain)
        
        // Try each recovery ID (0-3) - matching JS: for (let recoveryId = 0; recoveryId <= 3; recoveryId++)
        let recoveryIds: [UInt32] = [0, 1, 2, 3]
        var errors: [String] = []
        
        for recoveryId in recoveryIds {
            Logger.logDebug("Trying recovery ID \(recoveryId)...", category: .blockchain)
            
            do {
                // Try to build the transaction (this will simulate it)
                // If simulation succeeds without invalidSignature error, this recovery ID is correct
                let (_ , _) = try await buildClaimTransaction(
                    contractId: contractId,
                    claimant: claimant,
                    message: message,
                    signature: signature,
                    recoveryId: recoveryId,
                    publicKey: publicKey,
                    nonce: nonce,
                    sourceAccount: sourceKeyPair.accountId,
                    sourceKeyPair: sourceKeyPair
                )
                
                // If we get here, simulation succeeded - this is the correct recovery ID
                Logger.logDebug("Recovery ID \(recoveryId) is correct (simulation succeeded)", category: .blockchain)
                return recoveryId
            } catch {
                // Check if it's an invalidSignature error (wrong recovery ID)
                if case AppError.blockchain(.contract(.invalidSignature)) = error {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidSignature"
                    errors.append(errorMsg)
                    Logger.logDebug("Recovery ID \(recoveryId) failed with invalidSignature, trying next...", category: .blockchain)
                    continue
                }
                
                // Check for crypto errors (invalid recovery ID)
                let errorString = "\(error)"
                if errorString.contains("InvalidInput") ||
                   errorString.contains("recovery failed") ||
                   errorString.contains("recover_key_ecdsa") {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidInput"
                    errors.append(errorMsg)
                    Logger.logDebug("Recovery ID \(recoveryId) failed with crypto error, trying next...", category: .blockchain)
                    continue
                }
                
                // Other errors (like tokenAlreadyClaimed) mean the signature is valid
                // but there's a different issue - this recovery ID is correct
                Logger.logDebug("Recovery ID \(recoveryId) simulation failed with non-signature error, assuming this recovery ID is correct", category: .blockchain)
                return recoveryId
            }
        }
        
        // If we get here, no recovery ID worked
        if !errors.isEmpty {
            Logger.logError("Failed to determine recovery ID. Errors: \(errors.joined(separator: ", "))", category: .blockchain)
        }
        throw AppError.blockchain(.transactionFailed)
    }
    
    /// Build claim transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - claimant: Claimant address
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceAccount: Source account address
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Tuple with Transaction object (not signed) and the token ID from simulation
    /// - Throws: AppError if building fails
    func buildClaimTransaction(
        contractId: String,
        claimant: String,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceAccount: String,
        sourceKeyPair: KeyPair
    ) async throws -> (transaction: Transaction, tokenId: UInt64) {
        Logger.logDebug("buildClaimTransaction called", category: .blockchain)
        let claimantAddress = try SCAddressXDR(accountId: claimant)
        
        let args: [SCValXDR] = [
            SCValXDR.address(claimantAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        let transaction = try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "claim",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )
        
        // Extract token ID by simulating the transaction
        var tokenId: UInt64 = 0
        do {
            let returnValue = try await BlockchainHelpers.simulateAndDecode(transaction: transaction, rpcClient: rpcClient)
            if case .u64(let simulatedTokenId) = returnValue {
                tokenId = simulatedTokenId
            }
        } catch {
            // If simulation fails, tokenId remains 0
        }
        
        return (transaction: transaction, tokenId: tokenId)
    }

    /// Build transfer transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - from: Sender address
    ///   - to: Recipient address
    ///   - tokenId: Token ID to transfer
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Transaction object ready for signing
    /// - Throws: AppError if building fails
    func buildTransferTransaction(
        contractId: String,
        from: String,
        to: String,
        tokenId: UInt64,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> Transaction {
        let fromAddress = try SCAddressXDR(accountId: from)
        let toAddress = try SCAddressXDR(accountId: to)

        let args: [SCValXDR] = [
            SCValXDR.address(fromAddress),
            SCValXDR.address(toAddress),
            SCValXDR.u64(tokenId),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]

        return try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "transfer",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )
    }

    /// Build mint transaction
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - message: SEP-53 message (without nonce)
    ///   - signature: ECDSA signature (64 bytes: r + s)
    ///   - recoveryId: Recovery ID (0-3)
    ///   - publicKey: Chip public key (65 bytes, uncompressed)
    ///   - nonce: Nonce value
    ///   - sourceKeyPair: Source account keypair for signing
    /// - Returns: Tuple with Transaction object and the token ID from simulation
    /// - Throws: AppError if building fails
    func buildMintTransaction(
        contractId: String,
        message: Data,
        signature: Data,
        recoveryId: UInt32,
        publicKey: Data,
        nonce: UInt32,
        sourceKeyPair: KeyPair
    ) async throws -> (transaction: Transaction, tokenId: UInt64) {
        let args: [SCValXDR] = [
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]

        let transaction = try await BlockchainHelpers.buildTransaction(
            contractId: contractId,
            method: "mint",
            arguments: args,
            sourceKeyPair: sourceKeyPair
        )

        // Extract token ID by simulating the transaction
        var tokenId: UInt64 = 0
        do {
            let returnValue = try await BlockchainHelpers.simulateAndDecode(transaction: transaction, rpcClient: rpcClient)
            if case .u64(let simulatedTokenId) = returnValue {
                tokenId = simulatedTokenId
            }
        } catch {
            // If simulation fails, tokenId remains 0
        }

        return (transaction: transaction, tokenId: tokenId)
    }

    /// Submit transaction to network
    /// - Parameters:
    ///   - transaction: Signed transaction object (matching test script pattern)
    ///   - progressCallback: Optional callback for progress updates during polling
    /// - Returns: Transaction hash
    /// - Throws: AppError if submission fails
    func submitTransaction(_ transaction: Transaction, progressCallback: ((String) -> Void)? = nil) async throws -> String {
        Logger.logDebug("submitTransaction called", category: .blockchain)
        Logger.logDebug("RPC URL: \(config.rpcUrl)", category: .blockchain)
        
        // Verify transaction structure (matching JS validation)
        // Log transaction details for debugging
        Logger.logDebug("Transaction fee: \(transaction.fee)", category: .blockchain)
        Logger.logDebug("Transaction operations count: \(transaction.operations.count)", category: .blockchain)
        
        // Verify transaction has operations
        guard !transaction.operations.isEmpty else {
            Logger.logError("Transaction has no operations", category: .blockchain)
            throw AppError.blockchain(.transactionFailed)
        }
        
        // Verify transaction fee is valid (minimum 100 stroops per operation)
        let minFeePerOperation: Int64 = 100
        let requiredMinFee = minFeePerOperation * Int64(transaction.operations.count)
        if transaction.fee < requiredMinFee {
            Logger.logError("Transaction fee (\(transaction.fee)) is below minimum (\(requiredMinFee))", category: .blockchain)
            throw AppError.blockchain(.transactionFailed)
        }
        
        // Compute transaction hash before sending (needed for polling)
        let hashString = try BlockchainHelpers.getTransactionHash(transaction)
        
        progressCallback?("Sending transaction to blockchain network...")
        let sentTxResponse = await self.rpcClient.sendTransaction(transaction: transaction)
        
        let sentTx: SendTransactionResponse
        switch sentTxResponse {
        case .success(let response):
            sentTx = response
            Logger.logDebug("Transaction sent successfully", category: .blockchain)
            Logger.logDebug("SentTx: \(sentTx)", category: .blockchain)
            
            // Check for immediate errors in the response
            if sentTx.status == "ERROR" {
                Logger.logError("Transaction was immediately rejected with status: ERROR", category: .blockchain)
                if let errorResult = sentTx.errorResult {
                    Logger.logError("Error result code: \(errorResult.code)", category: .blockchain)
                    Logger.logDebug("Error result XDR: \(sentTx.errorResultXdr ?? "nil")", category: .blockchain)
                    
                    // Check for contract errors
                    let errorString = "\(errorResult)"
                    if let contractError = ContractError.fromErrorString(errorString) {
                        Logger.logError("Contract error detected: \(contractError)", category: .blockchain)
                        throw AppError.blockchain(.contract(contractError))
                    }
                    
                    // Handle specific error codes
                    switch errorResult.code {
                    case .malformed:
                        throw AppError.blockchain(.transactionRejected("Transaction was rejected as malformed. Please check your transaction parameters."))
                    case .badAuth:
                        throw AppError.blockchain(.transactionRejected("Transaction authentication failed. Please check your signature."))
                    case .badSeq:
                        throw AppError.blockchain(.transactionRejected("Transaction sequence number is incorrect."))
                    default:
                        throw AppError.blockchain(.transactionRejected("Transaction was rejected: \(errorResult.code)"))
                    }
                } else {
                    throw AppError.blockchain(.transactionRejected("Transaction was rejected by the network."))
                }
            }
            
            // If status is not PENDING or SUCCESS, don't poll
            if sentTx.status != "PENDING" && sentTx.status != "SUCCESS" {
                Logger.logDebug("Transaction status is '\(sentTx.status)', not polling", category: .blockchain)
                if sentTx.status == "SUCCESS" {
                    return hashString
                } else {
                    throw AppError.blockchain(.transactionRejected("Transaction status: \(sentTx.status)"))
                }
            }
        case .failure(let error):
            Logger.logError("ERROR sending transaction: \(error)", category: .blockchain)
            Logger.logError("Error type: \(type(of: error))", category: .blockchain)
            Logger.logError("Error details: \(error)", category: .blockchain)
            
            // Check for account not found errors
            let errorString = "\(error)"
            let errorLowercased = errorString.lowercased()
            if errorLowercased.contains("could not find account") || 
               errorLowercased.contains("account not found") ||
               errorLowercased.contains("does not exist") ||
               errorLowercased.contains("requestfailed") {
                throw AppError.wallet(.noWallet) // Account doesn't exist on network
            }
            
            // Use structured error parsing
            if let contractError = ContractError.fromErrorString(errorString) {
                Logger.logError("Contract error detected in send response: \(contractError)", category: .blockchain)
                throw AppError.blockchain(.contract(contractError))
            }
            
            throw AppError.blockchain(.transactionRejected("Failed to send transaction: \(error.localizedDescription)"))
        }
        
        // Poll for transaction confirmation with exponential backoff (Stellar SDK best practice)
        Logger.logDebug("Polling for transaction confirmation...", category: .blockchain)
            progressCallback?("Waiting for blockchain confirmation...")
        let maxAttempts = 10
        let maxPollingDuration: TimeInterval = 30.0 // Maximum 30 seconds total
        let initialDelay: TimeInterval = 0.5 // Start with 500ms
        let maxDelay: TimeInterval = 3.0 // Cap at 3 seconds
        var attempts = 0
        var currentDelay = initialDelay
        let startTime = Date()
        
        while attempts < maxAttempts {
            // Check if we've exceeded maximum polling duration
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > maxPollingDuration {
                Logger.logWarning("Transaction polling exceeded maximum duration (\(maxPollingDuration)s)", category: .blockchain)
                progressCallback?("Transaction confirmation timed out")
                throw AppError.blockchain(.transactionTimeout)
            }
            
            // Exponential backoff: wait with increasing delay
            let delayNanoseconds = UInt64(currentDelay * 1_000_000_000)
            Logger.logDebug("Waiting \(String(format: "%.2f", currentDelay))s before attempt \(attempts + 1)/\(maxAttempts)...", category: .blockchain)
                progressCallback?("Confirming transaction... (\(attempts + 1)/\(maxAttempts))")
            try await Task.sleep(nanoseconds: delayNanoseconds)
            
            let txResponseEnum = await self.rpcClient.getTransaction(transactionHash: hashString)
            
            switch txResponseEnum {
            case .success(let txResponse):
                Logger.logDebug("Transaction status: \(txResponse.status)", category: .blockchain)
                if txResponse.status == GetTransactionResponse.STATUS_SUCCESS {
                    Logger.logInfo("Transaction confirmed successfully!", category: .blockchain)
                    progressCallback?("Transaction confirmed!")
                    return hashString
                } else if txResponse.status == GetTransactionResponse.STATUS_FAILED {
                    Logger.logError("Transaction failed on network", category: .blockchain)
                    Logger.logDebug("Full response: \(txResponse)", category: .blockchain)
                    
                    // Use structured error parsing
                    let responseString = "\(txResponse)"
                    Logger.logDebug("Response string: \(responseString)", category: .blockchain)
                    
                    if let contractError = ContractError.fromErrorString(responseString) {
                        Logger.logError("Contract error detected in transaction response: \(contractError)", category: .blockchain)
                        throw AppError.blockchain(.contract(contractError))
                    }
                    
                    throw AppError.blockchain(.transactionFailed)
                } else {
                    // Transaction still pending, continue polling
                    attempts += 1
                    // Exponential backoff: double the delay, capped at maxDelay
                    currentDelay = min(currentDelay * 2.0, maxDelay)
                    continue
                }
            case .failure(let error):
                Logger.logWarning("Error getting transaction (attempt \(attempts + 1)/\(maxAttempts)): \(error)", category: .blockchain)
                attempts += 1
                // Exponential backoff: double the delay, capped at maxDelay
                currentDelay = min(currentDelay * 2.0, maxDelay)
                continue
            }
        }
        
        Logger.logWarning("Transaction polling timed out after \(attempts) attempts", category: .blockchain)
        throw AppError.blockchain(.transactionTimeout)
    }
}



