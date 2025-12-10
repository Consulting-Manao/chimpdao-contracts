import Foundation

protocol ContractFunction {
    var name: String { get }
    var requiresChipSignature: Bool { get }
    func execute(context: FunctionContext) async throws -> FunctionResult
}

struct FunctionContext {
    let contractId: String
    let walletConnection: WalletConnection
    let networkPassphrase: String
    let rpcUrl: String
    let horizonUrl: String
    let chipAuthData: ChipAuthData?
}

struct ChipAuthData {
    let publicKey: String
    let publicKeyBytes: Data
    let signature: Data
    let recoveryId: UInt32
    let message: Data
    let messageHash: Data
    let nonce: UInt32
}

struct FunctionResult {
    let success: Bool
    let message: String
    let data: [String: Any]?
}
