import Foundation

struct ScannedItem: Identifiable {
    let id = UUID()
    let contractId: String
    let tokenId: String?
    
    init(contractId: String, tokenId: String? = nil) {
        self.contractId = contractId
        self.tokenId = tokenId
    }
}
