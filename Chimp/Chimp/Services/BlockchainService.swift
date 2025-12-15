/**
 * Blockchain Service
 * Handles Soroban contract interactions
 */

import Foundation
import stellarsdk

class BlockchainService {
    private let config = AppConfig.shared
    
    /// Get owner of a token from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - tokenId: Token ID
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Owner address string
    /// - Throws: AppError if call fails
    func getTokenOwner(contractId: String, tokenId: UInt64, sourceKeyPair: KeyPair) async throws -> String {
        print("BlockchainService: getTokenOwner called")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Token ID: \(tokenId)")
        print("BlockchainService: Network: \(config.currentNetwork)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }

        let rpcClient = SorobanServer(endpoint: config.rpcUrl)

        // Build the contract call
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }

        print("BlockchainService: Creating ClientOptions with contractId: '\(contractId)'")
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")

        let args: [SCValXDR] = [
            SCValXDR.u64(tokenId)
        ]

        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "owner_of",
            arguments: args
        )

        // Build the transaction using SDK's AssembledTransaction
        // For read operations, we need to simulate to get the result
        print("BlockchainService: Building transaction...")
        print("BlockchainService: Method: owner_of")
        print("BlockchainService: Arguments count: \(args.count)")
        let assembledTx: AssembledTransaction
        do {
            // AssembledTransaction.build() handles:
            // - Transaction building
            // - Fee calculation
            // - Time bounds
            assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built successfully")
        } catch {
            print("BlockchainService: ERROR building transaction: \(error)")
            throw AppError.blockchain(.invalidResponse)
        }

        // For read operations, simulate to get the result
        guard let rawTx = assembledTx.raw else {
            print("BlockchainService: ERROR: No raw transaction")
            throw AppError.blockchain(.invalidResponse)
        }

        // Simulate to get the return value
        let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
        let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)

        switch simulateResponse {
        case .success(let simulateResult):
            print("BlockchainService: getTokenOwner simulation successful")
            guard let xdrString = simulateResult.results?.first?.xdr else {
                print("BlockchainService: No XDR string in simulation result")
                throw AppError.blockchain(.invalidResponse)
            }
            print("BlockchainService: XDR string: \(xdrString)")

            guard let xdrData = Data(base64Encoded: xdrString) else {
                print("BlockchainService: Failed to decode XDR string as base64")
                throw AppError.blockchain(.invalidResponse)
            }

            guard let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData) else {
                print("BlockchainService: Failed to decode XDR data")
                throw AppError.blockchain(.invalidResponse)
            }
            print("BlockchainService: Decoded return value: \(returnValue)")

            guard case .address(let address) = returnValue else {
                print("BlockchainService: Return value is not an address, it's: \(returnValue)")
                throw AppError.blockchain(.invalidResponse)
            }
            guard let ownerAddress = address.accountId else {
                print("BlockchainService: ERROR: Invalid account ID in address")
                throw AppError.blockchain(.invalidResponse)
            }
            print("BlockchainService: Token owner retrieved: \(ownerAddress)")
            return ownerAddress
        case .failure(let error):
            print("BlockchainService: getTokenOwner simulation failed: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")

            // Check if it's a contract error
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }

            throw AppError.blockchain(.invalidResponse)
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
        print("BlockchainService: getTokenUri called")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Contract ID length: \(contractId.count)")
        print("BlockchainService: Token ID: \(tokenId)")
        print("BlockchainService: Network: \(config.currentNetwork)")
        print("BlockchainService: Source account: \(sourceKeyPair.accountId)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }

        let rpcClient = SorobanServer(endpoint: config.rpcUrl)

        // Build the contract call
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }

        // Use the actual source account keypair (must exist on network)
        print("BlockchainService: Creating ClientOptions with contractId: '\(contractId)'")
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")

        let args: [SCValXDR] = [
            SCValXDR.u64(tokenId)
        ]

        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "token_uri",
            arguments: args
        )

        // Build the transaction using SDK's AssembledTransaction
        // For read operations, we need to simulate to get the result
        print("BlockchainService: Building transaction...")
        print("BlockchainService: Method: token_uri")
        print("BlockchainService: Arguments count: \(args.count)")
        let assembledTx: AssembledTransaction
        do {
            // AssembledTransaction.build() handles:
            // - Transaction building
            // - Fee calculation
            // - Time bounds
            assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built successfully")
        } catch {
            print("BlockchainService: ERROR building transaction: \(error)")
            throw AppError.blockchain(.invalidResponse)
        }

        // For read operations, simulate to get the result
        guard let rawTx = assembledTx.raw else {
            print("BlockchainService: ERROR: No raw transaction")
            throw AppError.blockchain(.invalidResponse)
        }

        // Simulate to get the return value
        let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
        let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)

        switch simulateResponse {
        case .success(let simulateResult):
            print("BlockchainService: Simulation successful")
            guard let xdrString = simulateResult.results?.first?.xdr,
                  let xdrData = Data(base64Encoded: xdrString),
                  let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData),
                  case .string(let uri) = returnValue else {
                print("BlockchainService: No token URI found in response")
                throw AppError.blockchain(.invalidResponse)
            }
            // Trim null bytes from the end of the URI
            let trimmedUri = uri.trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            print("BlockchainService: Token URI retrieved: \(trimmedUri)")

            return trimmedUri
        case .failure(let error):
            print("BlockchainService: Simulation failed: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")

            // Check if it's a contract error
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }

            throw AppError.blockchain(.invalidResponse)
        }
    }

    /// Get nonce for a public key from the contract
    /// - Parameters:
    ///   - contractId: Contract ID
    ///   - publicKey: Public key as Data (65 bytes, uncompressed)
    ///   - sourceKeyPair: Source account keypair (must exist on network)
    /// - Returns: Current nonce value, or 0 if not found
    /// - Throws: AppError if call fails
    func getNonce(contractId: String, publicKey: Data, sourceKeyPair: KeyPair) async throws -> UInt32 {
        print("BlockchainService: getNonce called")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Contract ID length: \(contractId.count)")
        print("BlockchainService: Network: \(config.currentNetwork)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Source account: \(sourceKeyPair.accountId)")
        
        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }
        
        let rpcClient = SorobanServer(endpoint: config.rpcUrl)
        
        // Build the contract call
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        // Use the actual source account keypair (must exist on network)
        print("BlockchainService: Creating ClientOptions with contractId: '\(contractId)'")
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")
        
        let args: [SCValXDR] = [
            SCValXDR.bytes(publicKey)
        ]
        
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "get_nonce",
            arguments: args
        )
        
        // Build the transaction using SDK's AssembledTransaction
        // For read operations, we need to simulate to get the result
        print("BlockchainService: Building transaction...")
        print("BlockchainService: Method: get_nonce")
        print("BlockchainService: Arguments count: \(args.count)")
        let assembledTx: AssembledTransaction
        do {
            // AssembledTransaction.build() handles:
            // - Transaction building
            // - Fee calculation
            // - Time bounds
            assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built successfully")
        } catch {
            print("BlockchainService: ERROR building transaction: \(error)")
            // If build fails, return 0 (first use, contract might not have nonce set yet)
            return 0
        }
        
        // For read operations, simulate to get the result
        guard let rawTx = assembledTx.raw else {
            print("BlockchainService: ERROR: No raw transaction")
            return 0
        }
        
        // Simulate to get the return value
        let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
        let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)
        
        switch simulateResponse {
        case .success(let simulateResult):
            print("BlockchainService: Simulation successful")
            guard let xdrString = simulateResult.results?.first?.xdr,
                  let xdrData = Data(base64Encoded: xdrString),
                  let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData),
                  case .u32(let nonce) = returnValue else {
                print("BlockchainService: No nonce found in response, defaulting to 0")
                return 0
            }
            print("BlockchainService: Nonce retrieved: \(nonce)")
            return nonce
        case .failure(let error):
            print("BlockchainService: Simulation failed: \(error)")
            // If simulation fails, return 0 (first use)
            return 0
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
        print("BlockchainService: determineRecoveryId called (offline, using contract simulation)")
        
        // Try each recovery ID (0-3) - matching JS: for (let recoveryId = 0; recoveryId <= 3; recoveryId++)
        let recoveryIds: [UInt32] = [0, 1, 2, 3]
        var errors: [String] = []
        
        for recoveryId in recoveryIds {
            print("BlockchainService: Trying recovery ID \(recoveryId)...")
            
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
                print("BlockchainService: Recovery ID \(recoveryId) is correct (simulation succeeded)")
                return recoveryId
            } catch {
                // Check if it's an invalidSignature error (wrong recovery ID)
                if case AppError.blockchain(.contract(.invalidSignature)) = error {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidSignature"
                    errors.append(errorMsg)
                    print("BlockchainService: Recovery ID \(recoveryId) failed with invalidSignature, trying next...")
                    continue
                }
                
                // Check for crypto errors (invalid recovery ID)
                let errorString = "\(error)"
                if errorString.contains("InvalidInput") ||
                   errorString.contains("recovery failed") ||
                   errorString.contains("recover_key_ecdsa") {
                    let errorMsg = "Recovery ID \(recoveryId): InvalidInput"
                    errors.append(errorMsg)
                    print("BlockchainService: Recovery ID \(recoveryId) failed with crypto error, trying next...")
                    continue
                }
                
                // Other errors (like tokenAlreadyClaimed) mean the signature is valid
                // but there's a different issue - this recovery ID is correct
                print("BlockchainService: Recovery ID \(recoveryId) simulation failed with non-signature error, assuming this recovery ID is correct")
                return recoveryId
            }
        }
        
        // If we get here, no recovery ID worked
        _ = errors.isEmpty ? "" : "\nErrors encountered:\n\(errors.joined(separator: "\n"))"
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
        print("BlockchainService: buildClaimTransaction called")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Contract ID length: \(contractId.count)")
        print("BlockchainService: Claimant: \(claimant)")
        print("BlockchainService: Message length: \(message.count)")
        print("BlockchainService: Signature length: \(signature.count)")
        print("BlockchainService: Recovery ID: \(recoveryId)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Nonce: \(nonce)")
        
        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }
        
        // Create SCValXDR arguments
        let claimantAddress = try SCAddressXDR(accountId: claimant)
        
        let args: [SCValXDR] = [
            SCValXDR.address(claimantAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        // Create client options
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        print("BlockchainService: Network: \(network)")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")

        let rpcClient = SorobanServer(endpoint: config.rpcUrl)

        print("BlockchainService: Creating ClientOptions with contractId: '\(contractId)'")
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")
        
        // Create assembled transaction options
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "claim",
            arguments: args
        )
        
        // Build the transaction using SDK's AssembledTransaction
        // This automatically handles: simulation, fee calculation, time bounds, and validation
        print("BlockchainService: Building claim transaction...")
        print("BlockchainService: Method: claim")
        print("BlockchainService: Arguments count: \(args.count)")
        do {
            // AssembledTransaction.build() handles:
            // - Transaction building
            // - Simulation (to verify it will succeed)
            // - Fee calculation
            // - Time bounds setting
            // - Resource limits
            let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built and simulated successfully")

            // Extract token ID by simulating the transaction directly
            var tokenId: UInt64 = 0
            if let rawTx = assembledTx.raw {
                let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
                let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)

                if case .success(let simulateResult) = simulateResponse,
                   let xdrString = simulateResult.results?.first?.xdr,
                   let xdrData = Data(base64Encoded: xdrString),
                   let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData),
                   case .u64(let simulatedTokenId) = returnValue {
                    tokenId = simulatedTokenId
                    print("BlockchainService: Token ID from simulation: \(tokenId)")
                } else {
                    print("BlockchainService: WARNING: Could not extract token ID from simulation, using 0")
                }
            }

            // Get the Transaction object (not signed yet)
            // The SDK has already validated everything during build()
            guard let rawTx = assembledTx.raw else {
                print("BlockchainService: ERROR: Failed to get Transaction from AssembledTransaction")
                throw AppError.blockchain(.transactionFailed)
            }

            print("BlockchainService: Transaction ready for signing")
            print("BlockchainService: Transaction operations count: \(rawTx.operations.count)")
            print("BlockchainService: Transaction fee: \(rawTx.fee) stroops")

            // Return the Transaction object and token ID - SDK has already handled all validation
            return (transaction: rawTx, tokenId: tokenId)
        } catch {
            print("BlockchainService: ERROR building transaction: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")
            
            // Check if it's a contract error
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }
            
            throw error
        }
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
        print("BlockchainService: buildTransferTransaction called")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: From: \(from)")
        print("BlockchainService: To: \(to)")
        print("BlockchainService: Token ID: \(tokenId)")
        print("BlockchainService: Message length: \(message.count)")
        print("BlockchainService: Signature length: \(signature.count)")
        print("BlockchainService: Recovery ID: \(recoveryId)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Nonce: \(nonce)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }

        // Create SCValXDR arguments
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

        // Create client options
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }

        print("BlockchainService: Network: \(network)")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")

        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")

        // Create assembled transaction options
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "transfer",
            arguments: args
        )

        // Build the transaction using SDK's AssembledTransaction
        print("BlockchainService: Building transfer transaction...")
        print("BlockchainService: Method: transfer")
        print("BlockchainService: Arguments count: \(args.count)")
        do {
            let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built and simulated successfully")

            // Get the Transaction object (not signed yet)
            guard let rawTx = assembledTx.raw else {
                print("BlockchainService: ERROR: Failed to get Transaction from AssembledTransaction")
                throw AppError.blockchain(.transactionFailed)
            }

            print("BlockchainService: Transaction ready for signing")
            print("BlockchainService: Transaction operations count: \(rawTx.operations.count)")
            print("BlockchainService: Transaction fee: \(rawTx.fee) stroops")

            return rawTx
        } catch {
            print("BlockchainService: ERROR building transfer transaction: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")

            // Check if it's a contract error
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }

            throw error
        }
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
        print("BlockchainService: buildMintTransaction called")
        print("BlockchainService: Contract ID: \(contractId)")
        print("BlockchainService: Message length: \(message.count)")
        print("BlockchainService: Signature length: \(signature.count)")
        print("BlockchainService: Recovery ID: \(recoveryId)")
        print("BlockchainService: Public key length: \(publicKey.count)")
        print("BlockchainService: Nonce: \(nonce)")

        // Validate contract ID format
        guard config.validateContractId(contractId) else {
            print("BlockchainService: ERROR: Invalid contract ID format: \(contractId)")
            throw AppError.blockchain(.invalidResponse)
        }

        let args: [SCValXDR] = [
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]

        // Create client options
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }

        print("BlockchainService: Network: \(network)")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")

        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: config.rpcUrl
        )
        print("BlockchainService: ClientOptions created successfully")

        // Create assembled transaction options
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "mint",
            arguments: args
        )

        // Build the transaction using SDK's AssembledTransaction
        print("BlockchainService: Building mint transaction...")
        print("BlockchainService: Method: mint")
        print("BlockchainService: Arguments count: \(args.count)")
        do {
            let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
            print("BlockchainService: Transaction built and simulated successfully")

            // Extract token ID by simulating the transaction directly
            var tokenId: UInt64 = 0
            let rpcClient = SorobanServer(endpoint: config.rpcUrl)
            if let rawTx = assembledTx.raw {
                let simulateRequest = SimulateTransactionRequest(transaction: rawTx)
                let simulateResponse = await rpcClient.simulateTransaction(simulateTxRequest: simulateRequest)

                if case .success(let simulateResult) = simulateResponse,
                   let xdrString = simulateResult.results?.first?.xdr,
                   let xdrData = Data(base64Encoded: xdrString),
                   let returnValue = try? XDRDecoder.decode(SCValXDR.self, data: xdrData),
                   case .u64(let simulatedTokenId) = returnValue {
                    tokenId = simulatedTokenId
                    print("BlockchainService: Token ID from simulation: \(tokenId)")
                } else {
                    print("BlockchainService: WARNING: Could not extract token ID from simulation, using 0")
                }
            }

            // Get the Transaction object (not signed yet)
            guard let rawTx = assembledTx.raw else {
                print("BlockchainService: ERROR: Failed to get Transaction from AssembledTransaction")
                throw AppError.blockchain(.transactionFailed)
            }

            print("BlockchainService: Transaction ready for signing")
            print("BlockchainService: Transaction operations count: \(rawTx.operations.count)")
            print("BlockchainService: Transaction fee: \(rawTx.fee) stroops")

            return (transaction: rawTx, tokenId: tokenId)
        } catch {
            print("BlockchainService: ERROR building mint transaction: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")

            // Check if it's a contract error
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }

            throw error
        }
    }

    /// Submit transaction to network
    /// - Parameters:
    ///   - transaction: Signed transaction object (matching test script pattern)
    ///   - progressCallback: Optional callback for progress updates during polling
    /// - Returns: Transaction hash
    /// - Throws: AppError if submission fails
    func submitTransaction(_ transaction: Transaction, progressCallback: ((String) -> Void)? = nil) async throws -> String {
        print("BlockchainService: submitTransaction called")
        print("BlockchainService: RPC URL: \(config.rpcUrl)")
        
        // Verify transaction structure (matching JS validation)
        // Log transaction details for debugging
        print("BlockchainService: Transaction fee: \(transaction.fee)")
        print("BlockchainService: Transaction operations count: \(transaction.operations.count)")
        
        // Verify transaction has operations
        guard !transaction.operations.isEmpty else {
            print("BlockchainService: ERROR: Transaction has no operations")
            throw AppError.blockchain(.transactionFailed)
        }
        
        // Verify transaction fee is valid (minimum 100 stroops per operation)
        let minFeePerOperation: Int64 = 100
        let requiredMinFee = minFeePerOperation * Int64(transaction.operations.count)
        if transaction.fee < requiredMinFee {
            print("BlockchainService: ERROR: Transaction fee (\(transaction.fee)) is below minimum (\(requiredMinFee))")
            throw AppError.blockchain(.transactionFailed)
        }
        
        // Compute transaction hash before sending (needed for polling)
        let network: Network
        switch config.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        let hashString = try transaction.getTransactionHash(network: network)
        print("BlockchainService: Transaction hash: \(hashString)")
        
        // Send the transaction object directly (matching test script: rpcClient.sendTransaction(transaction: transaction))
        // This matches the JS pattern: rpcServer.sendTransaction(transaction)
        let rpcClient = SorobanServer(endpoint: config.rpcUrl)
        print("BlockchainService: Sending transaction to RPC...")
        progressCallback?("Sending transaction to network...")
        let sentTxResponse = await rpcClient.sendTransaction(transaction: transaction)
        
        let sentTx: SendTransactionResponse
        switch sentTxResponse {
        case .success(let response):
            sentTx = response
            print("BlockchainService: Transaction sent successfully")
            print("BlockchainService: SentTx: \(sentTx)")
            
            // Check for immediate errors in the response
            if sentTx.status == "ERROR" {
                print("BlockchainService: Transaction was immediately rejected with status: ERROR")
                if let errorResult = sentTx.errorResult {
                    print("BlockchainService: Error result code: \(errorResult.code)")
                    print("BlockchainService: Error result XDR: \(sentTx.errorResultXdr ?? "nil")")
                    
                    // Check for contract errors
                    let errorString = "\(errorResult)"
                    if let contractError = ContractError.fromErrorString(errorString) {
                        print("BlockchainService: Contract error detected: \(contractError)")
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
                print("BlockchainService: Transaction status is '\(sentTx.status)', not polling")
                if sentTx.status == "SUCCESS" {
                    return hashString
                } else {
                    throw AppError.blockchain(.transactionRejected("Transaction status: \(sentTx.status)"))
                }
            }
        case .failure(let error):
            print("BlockchainService: ERROR sending transaction: \(error)")
            print("BlockchainService: Error type: \(type(of: error))")
            print("BlockchainService: Error details: \(error)")
            
            // Use structured error parsing
            let errorString = "\(error)"
            if let contractError = ContractError.fromErrorString(errorString) {
                print("BlockchainService: Contract error detected in send response: \(contractError)")
                throw AppError.blockchain(.contract(contractError))
            }
            
            throw AppError.blockchain(.transactionRejected("Failed to send transaction: \(error.localizedDescription)"))
        }
        
        // Poll for transaction confirmation with exponential backoff (Stellar SDK best practice)
        print("BlockchainService: Polling for transaction confirmation...")
        progressCallback?("Waiting for transaction confirmation...")
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
                print("BlockchainService: Transaction polling exceeded maximum duration (\(maxPollingDuration)s)")
                progressCallback?("Transaction confirmation timed out")
                throw AppError.blockchain(.transactionTimeout)
            }
            
            // Exponential backoff: wait with increasing delay
            let delayNanoseconds = UInt64(currentDelay * 1_000_000_000)
            print("BlockchainService: Waiting \(String(format: "%.2f", currentDelay))s before attempt \(attempts + 1)/\(maxAttempts)...")
            progressCallback?("Checking transaction status... (\(attempts + 1)/\(maxAttempts))")
            try await Task.sleep(nanoseconds: delayNanoseconds)
            
            let txResponseEnum = await rpcClient.getTransaction(transactionHash: hashString)
            
            switch txResponseEnum {
            case .success(let txResponse):
                print("BlockchainService: Transaction status: \(txResponse.status)")
                if txResponse.status == GetTransactionResponse.STATUS_SUCCESS {
                    print("BlockchainService: Transaction confirmed successfully!")
                    progressCallback?("Transaction confirmed!")
                    return hashString
                } else if txResponse.status == GetTransactionResponse.STATUS_FAILED {
                    print("BlockchainService: Transaction failed on network")
                    print("BlockchainService: Full response: \(txResponse)")
                    
                    // Use structured error parsing
                    let responseString = "\(txResponse)"
                    print("BlockchainService: Response string: \(responseString)")
                    
                    if let contractError = ContractError.fromErrorString(responseString) {
                        print("BlockchainService: Contract error detected in transaction response: \(contractError)")
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
                print("BlockchainService: Error getting transaction (attempt \(attempts + 1)/\(maxAttempts)): \(error)")
                attempts += 1
                // Exponential backoff: double the delay, capped at maxDelay
                currentDelay = min(currentDelay * 2.0, maxDelay)
                continue
            }
        }
        
        print("BlockchainService: Transaction polling timed out after \(attempts) attempts")
        throw AppError.blockchain(.transactionTimeout)
    }
}



