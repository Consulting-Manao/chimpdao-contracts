import Foundation
import UIKit
import CoreNFC
import stellarsdk
import OSLog

/// Coordinator to bridge SwiftUI to existing UIKit NFC functionality
/// Refactored to use NFCManager for consolidated session management
class NFCOperationCoordinator: NSObject {
    private let nfcManager = NFCManager()
    
    // Callbacks (preserved for HomeViewModel integration)
    var onLoadNFTSuccess: ((String, UInt64) -> Void)?
    var onLoadNFTError: ((String) -> Void)?
    var onClaimSuccess: ((UInt64, String) -> Void)? // tokenId, contractId
    var onClaimError: ((String) -> Void)?
    var onTransferSuccess: (() -> Void)?
    var onTransferError: ((String) -> Void)?
    var onSignSuccess: ((UInt32, UInt32, String) -> Void)? // globalCounter, keyCounter, signature
    var onSignError: ((String) -> Void)?
    var onMintSuccess: ((UInt64) -> Void)? // tokenId
    var onMintError: ((String) -> Void)?
    
    // MARK: - Load NFT
    func loadNFT(completion: @escaping (Bool, String?) -> Void) {
        nfcManager.loadNFT { [weak self] success, error, contractId, tokenId in
            completion(success, error)
            if success, let contractId = contractId, let tokenId = tokenId {
                self?.onLoadNFTSuccess?(contractId, tokenId)
            } else if let error = error {
                self?.onLoadNFTError?(error)
            }
        }
    }
    
    // MARK: - Claim NFT
    func claimNFT(completion: @escaping (Bool, String?) -> Void) {
        nfcManager.claimNFT { [weak self] success, error, tokenId, contractId in
            completion(success, error)
            if success, let tokenId = tokenId, let contractId = contractId {
                self?.onClaimSuccess?(tokenId, contractId)
            } else if let error = error {
                self?.onClaimError?(error)
            }
        }
    }
    
    // MARK: - Read NFT for Transfer (first scan to get token ID)
    func readNFTForTransfer(completion: @escaping (Bool, UInt64?, String?) -> Void) {
        nfcManager.readNFTForTransfer { success, tokenId, error in
            completion(success, tokenId, error)
            // No specific callbacks for this operation - just direct completion
        }
    }
    
    // MARK: - Transfer NFT (second scan to complete transfer)
    func transferNFT(recipientAddress: String, tokenId: UInt64, completion: @escaping (Bool, String?) -> Void) {
        nfcManager.transferNFT(recipientAddress: recipientAddress, tokenId: tokenId) { [weak self] success, error in
            completion(success, error)
            if success {
                self?.onTransferSuccess?()
            } else if let error = error {
                self?.onTransferError?(error)
            }
        }
    }
    
    // MARK: - Sign Message
    func signMessage(message: Data, completion: @escaping (Bool, UInt32?, UInt32?, String?) -> Void) {
        nfcManager.signMessage(message: message) { [weak self] success, globalCounter, keyCounter, derSignature, error in
            completion(success, globalCounter, keyCounter, derSignature)
            if success, let globalCounter = globalCounter, let keyCounter = keyCounter, let derSignature = derSignature {
                self?.onSignSuccess?(globalCounter, keyCounter, derSignature)
            } else if let error = error {
                self?.onSignError?(error)
            }
        }
    }
    
    // MARK: - Mint NFT
    func mintNFT(completion: @escaping (Bool, String?) -> Void) {
        nfcManager.mintNFT { [weak self] success, error, tokenId in
            completion(success, error)
            if success, let tokenId = tokenId {
                self?.onMintSuccess?(tokenId)
            } else if let error = error {
                self?.onMintError?(error)
            }
        }
    }
}

