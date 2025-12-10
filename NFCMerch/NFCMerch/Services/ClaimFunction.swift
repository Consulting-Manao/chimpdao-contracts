import Foundation
import stellarsdk

class ClaimFunction {
    func executeClaim(
        contractId: String,
        tokenId: UInt64,
        context: FunctionContext,
        nfcService: NFCService,
        blockchainService: BlockchainService,
        walletService: WalletService,
        stepCallback: @escaping (ClaimView.ClaimStep) -> Void
    ) async throws -> FunctionResult {
        guard let wallet = context.walletConnection as? WalletConnection else {
            throw ClaimError.noWallet
        }
        
        stepCallback(.reading)
        
        let nonce: UInt32 = 0
        
        let sep53Result = try createSEP53Message(
            contractId: contractId,
            functionName: "claim",
            args: [wallet.address, String(tokenId)] as [Any],
            nonce: nonce,
            networkPassphrase: context.networkPassphrase
        )
        
        stepCallback(.signing)
        
        let chipPublicKey = try await readChipPublicKey(nfcService: nfcService)
        let signatureResult = try await signWithChip(
            nfcService: nfcService,
            messageHash: sep53Result.messageHash
        )
        
        stepCallback(.recovering)
        
        let recoveryId = try await determineRecoveryId(
            messageHash: sep53Result.messageHash,
            signature: signatureResult.signatureBytes,
            expectedPublicKey: chipPublicKey
        )
        
        let publicKeyBytes = hexToBytes(chipPublicKey)
        guard publicKeyBytes.count == 65 else {
            throw ClaimError.invalidPublicKey
        }
        
        stepCallback(.calling)
        
        // Get KeyPair for building transaction
        let sourceKeyPair: stellarsdk.KeyPair
        if case .manual = wallet.type {
            let dummyTx = Data("dummy".utf8)
            let _ = try await walletService.signTransaction(transaction: dummyTx, wallet: wallet)
            sourceKeyPair = try stellarsdk.KeyPair(accountId: wallet.address)
        } else {
            sourceKeyPair = try stellarsdk.KeyPair(accountId: wallet.address)
        }
        
        let transactionXdr = try await blockchainService.buildClaimTransaction(
            contractId: contractId,
            claimant: wallet.address,
            message: sep53Result.message,
            signature: signatureResult.signatureBytes,
            recoveryId: recoveryId,
            publicKey: publicKeyBytes,
            nonce: nonce,
            sourceAccount: wallet.address,
            sourceKeyPair: sourceKeyPair
        )
        
        let signedTx = try await walletService.signTransaction(
            transaction: transactionXdr,
            wallet: wallet
        )
        
        stepCallback(.confirming)
        
        let txHash = try await blockchainService.submitTransaction(signedTx)
        
        return FunctionResult(
            success: true,
            message: "Claim successful. Transaction: \(txHash)",
            data: ["txHash": txHash, "tokenId": String(tokenId)]
        )
    }
    
    private func readChipPublicKey(nfcService: NFCService) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            nfcService.readPublicKey { result in
                switch result {
                case .success(let publicKey):
                    continuation.resume(returning: publicKey)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func signWithChip(
        nfcService: NFCService,
        messageHash: Data
    ) async throws -> (signatureBytes: Data, recoveryId: UInt8) {
        return try await withCheckedThrowingContinuation { continuation in
            nfcService.signMessage(messageHash: messageHash) { result in
                switch result {
                case .success(let (r, s, recoveryId)):
                    let rBytes = hexToBytes(r)
                    let sBytes = hexToBytes(s)
                    
                    var signatureBytes = Data()
                    signatureBytes.append(rBytes)
                    signatureBytes.append(sBytes)
                    
                    guard signatureBytes.count == 64 else {
                        continuation.resume(throwing: ClaimError.invalidSignature)
                        return
                    }
                    
                    continuation.resume(returning: (
                        signatureBytes: signatureBytes,
                        recoveryId: UInt8(recoveryId)
                    ))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

enum ClaimError: Error, LocalizedError {
    case noWallet
    case invalidPublicKey
    case invalidSignature
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .noWallet:
            return "No wallet connected"
        case .invalidPublicKey:
            return "Invalid public key format"
        case .invalidSignature:
            return "Invalid signature format"
        case .transactionFailed:
            return "Transaction failed"
        }
    }
}
