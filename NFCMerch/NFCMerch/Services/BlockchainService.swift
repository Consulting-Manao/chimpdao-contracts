import Foundation
import stellarsdk

/// Service for interacting with Stellar/Soroban blockchain
class BlockchainService {
    
    /// Fetch current ledger sequence number from Horizon API
    func fetchCurrentLedger() async throws -> UInt32 {
        let urlString = "\(NFCConfig.horizonUrl)/ledgers?order=desc&limit=1"
        guard let url = URL(string: urlString) else {
            throw BlockchainError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlockchainError.httpError
        }
        
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedded = json["_embedded"] as? [String: Any],
              let records = embedded["records"] as? [[String: Any]],
              let firstRecord = records.first,
              let sequence = firstRecord["sequence"] else {
            throw BlockchainError.invalidResponse
        }
        
        // Sequence can be string or number
        if let sequenceStr = sequence as? String, let seq = UInt32(sequenceStr) {
            return seq
        } else if let seq = sequence as? UInt32 {
            return seq
        } else if let seqInt = sequence as? Int {
            let seq = UInt32(seqInt)
            return seq
        }
        
        throw BlockchainError.invalidSequence
    }
    
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
        sourceAccount: String,
        sourceKeyPair: KeyPair
    ) async throws -> Data {
        // Create SCValXDR arguments
        let fromAddress = try SCAddressXDR(accountId: from)
        let toAddress = try SCAddressXDR(accountId: to)
        
        let args: [SCValXDR] = [
            try SCValXDR.address(fromAddress),
            try SCValXDR.address(toAddress),
            SCValXDR.u64(tokenId),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        // Create client options
        let network: Network
        switch NFCConfig.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: NFCConfig.rpcUrl
        )
        
        // Create assembled transaction options (methodOptions must come before method)
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "transfer",
            arguments: args
        )
        
        // Build the transaction
        let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        
        // Get the transaction XDR from the raw transaction
        guard let rawTx = assembledTx.raw,
              let xdrString = rawTx.xdrEncoded else {
            throw BlockchainError.transactionFailed
        }
        return Data(base64Encoded: xdrString) ?? Data()
    }
    
    func buildMintTransaction(
        contractId: String,
        to: String,
        message: Data,
        signature: Data,
        recoveryId: UInt8,
        tokenId: Data,
        nonce: UInt32,
        sourceAccount: String,
        sourceKeyPair: KeyPair
    ) async throws -> Data {
        // Create SCValXDR arguments
        let toAddress = try SCAddressXDR(accountId: to)
        
        let args: [SCValXDR] = [
            try SCValXDR.address(toAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(UInt32(recoveryId)),
            SCValXDR.bytes(tokenId),
            SCValXDR.u32(nonce)
        ]
        
        // Create client options
        let network: Network
        switch NFCConfig.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: NFCConfig.rpcUrl
        )
        
        // Create assembled transaction options (methodOptions must come before method)
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "mint",
            arguments: args
        )
        
        // Build the transaction
        let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        
        // Get the transaction XDR from the raw transaction
        guard let rawTx = assembledTx.raw,
              let xdrString = rawTx.xdrEncoded else {
            throw BlockchainError.transactionFailed
        }
        return Data(base64Encoded: xdrString) ?? Data()
    }
    
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
    ) async throws -> Data {
        // Create SCValXDR arguments
        let claimantAddress = try SCAddressXDR(accountId: claimant)
        
        let args: [SCValXDR] = [
            try SCValXDR.address(claimantAddress),
            SCValXDR.bytes(message),
            SCValXDR.bytes(signature),
            SCValXDR.u32(recoveryId),
            SCValXDR.bytes(publicKey),
            SCValXDR.u32(nonce)
        ]
        
        // Create client options
        let network: Network
        switch NFCConfig.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: sourceKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: NFCConfig.rpcUrl
        )
        
        // Create assembled transaction options (methodOptions must come before method)
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "claim",
            arguments: args
        )
        
        // Build the transaction
        let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        
        // Get the transaction XDR from the raw transaction
        guard let rawTx = assembledTx.raw,
              let xdrString = rawTx.xdrEncoded else {
            throw BlockchainError.transactionFailed
        }
        return Data(base64Encoded: xdrString) ?? Data()
    }
    
    func submitTransaction(_ transactionXdr: Data) async throws -> String {
        let rpcUrlString = NFCConfig.rpcUrl
        let rpcClient = SorobanServer(endpoint: rpcUrlString)
        
        // Convert XDR Data to Transaction object
        let transactionXdrString = transactionXdr.base64EncodedString()
        let stellarTransaction = try Transaction(envelopeXdr: transactionXdrString)
        
        let sentTxResponse = await rpcClient.sendTransaction(transaction: stellarTransaction)
        
        guard case .success(let sentTx) = sentTxResponse else {
            throw BlockchainError.transactionRejected
        }
        
        let maxAttempts = 10
        var attempts = 0
        
        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            let hashString = String(sentTx.hash)
            let txResponseEnum = await rpcClient.getTransaction(transactionHash: hashString)
            
            guard case .success(let txResponse) = txResponseEnum else {
                attempts += 1
                continue
            }
            
            if txResponse.status == GetTransactionResponse.STATUS_SUCCESS {
                return hashString
            } else if txResponse.status == GetTransactionResponse.STATUS_FAILED {
                throw BlockchainError.transactionFailed
            } else {
                attempts += 1
                continue
            }
        }
        
        throw BlockchainError.transactionTimeout
    }
    
    func getAccount(_ address: String) async throws -> AccountResponse {
        let urlString = "\(NFCConfig.horizonUrl)/accounts/\(address)"
        guard let url = URL(string: urlString) else {
            throw BlockchainError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlockchainError.httpError
        }
        
        let accountResponse = try JSONDecoder().decode(AccountResponse.self, from: data)
        return accountResponse
    }
    
    func getOwnerOf(contractId: String, tokenId: UInt64) async throws -> String {
        // Call contract's owner_of function via RPC
        let rpcUrlString = NFCConfig.rpcUrl
        let rpcClient = SorobanServer(endpoint: rpcUrlString)
        
        // Build the contract call
        let network: Network
        switch NFCConfig.currentNetwork {
        case .testnet:
            network = .testnet
        case .mainnet:
            network = .public
        }
        
        // Create a dummy keypair for the call (we're just reading, not writing)
        let dummyKeyPair = try KeyPair.generateRandomKeyPair()
        let clientOptions = ClientOptions(
            sourceAccountKeyPair: dummyKeyPair,
            contractId: contractId,
            network: network,
            rpcUrl: rpcUrlString
        )
        
        let args: [SCValXDR] = [
            SCValXDR.u64(tokenId)
        ]
        
        let assembledOptions = AssembledTransactionOptions(
            clientOptions: clientOptions,
            methodOptions: MethodOptions(),
            method: "owner_of",
            arguments: args
        )
        
        // Simulate the call to get the result
        let assembledTx = try await AssembledTransaction.build(options: assembledOptions)
        
        // Simulate the transaction to get the return value
        let simulateResponse = await rpcClient.simulateTransaction(transaction: assembledTx.raw!)
        
        guard case .success(let simulateResult) = simulateResponse,
              let returnValue = simulateResult.results?.first?.xdr,
              case .address(let addressXDR) = returnValue else {
            throw BlockchainError.invalidResponse
        }
        
        // Extract address from SCAddressXDR
        switch addressXDR {
        case .account(let accountId):
            return accountId.accountId
        case .contract(let contractIdBytes):
            // Contract address - convert to string representation
            let contractIdString = contractIdBytes.wrapped.base64EncodedString()
            return contractIdString
        }
    }
}

enum BlockchainError: Error, LocalizedError {
    case invalidURL
    case httpError
    case invalidResponse
    case invalidSequence
    case notImplemented
    case transactionRejected
    case transactionFailed
    case transactionTimeout
    case accountNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError:
            return "HTTP request failed"
        case .invalidResponse:
            return "Invalid response format"
        case .invalidSequence:
            return "Invalid ledger sequence"
        case .notImplemented:
            return "Feature not yet implemented - SDK integration required"
        case .transactionRejected:
            return "Transaction was rejected by the network"
        case .transactionFailed:
            return "Transaction failed on the network"
        case .transactionTimeout:
            return "Transaction submission timed out"
        case .accountNotFound:
            return "Account not found"
        }
    }
}

struct AccountResponse: Codable {
    let accountId: String
    let sequence: String
    
    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case sequence
    }
    
    var sequenceNumber: Int64 {
        return Int64(sequence) ?? 0
    }
}
