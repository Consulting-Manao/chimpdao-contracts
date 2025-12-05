/**
 * NFC Service
 * Manages NFCISO7816TagReaderSession and APDU communication with SECORA chip
 */

import Foundation
import CoreNFC

class NFCService {
    weak var delegate: NFCServiceDelegate?
    
    private var session: NFCISO7816TagReaderSession?
    private var currentTag: NFCISO7816Tag?
    var tagConnected: NFCISO7816Tag? {
        get { currentTag }
        set {
            currentTag = newValue
            if newValue != nil {
                // Tag connected, can proceed with operations
                tagConnectedCallback?()
            }
        }
    }
    
    private var tagConnectedCallback: (() -> Void)?
    
    /**
     * Start NFC session
     */
    func startSession() {
        guard NFCNDEFReaderSession.readingAvailable else {
            delegate?.nfcService(self, didFailWithError: NFCError(.readerSessionUnsupportedFeature))
            return
        }
        
        session = NFCISO7816TagReaderSession(
            delegate: NFCSessionDelegate(service: self),
            queue: DispatchQueue.global(qos: .userInitiated),
            invalidateAfterFirstRead: false
        )
        
        session?.alertMessage = "Hold your device near the NFC chip"
        session?.begin()
    }
    
    /**
     * Stop NFC session
     */
    func stopSession() {
        session?.invalidate()
        session = nil
        currentTag = nil
    }
    
    /**
     * Session was invalidated
     */
    func sessionInvalidated(error: Error) {
        currentTag = nil
        session = nil
        
        // Only report errors (not user cancellation)
        if let nfcError = error as? NFCReaderError {
            if nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                delegate?.nfcService(self, didFailWithError: error)
            }
        } else {
            delegate?.nfcService(self, didFailWithError: error)
        }
    }
    
    /**
     * Send APDU command to chip
     */
    func sendAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            // Need to start session and wait for tag
            tagConnectedCallback = { [weak self] in
                self?.executeAPDU(apdu, completion: completion)
            }
            startSession()
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU after tag is connected
     */
    private func executeAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            completion(.failure(NFCError(.tagConnectionLost)))
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU on specific tag
     */
    private func executeAPDUOnTag(_ tag: NFCISO7816Tag, apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        tag.sendCommand(
            apdu: apdu,
            completionHandler: { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Combine response data with status word
                var fullResponse = response
                fullResponse.append(sw1)
                fullResponse.append(sw2)
                
                completion(.success(fullResponse))
            }
        )
    }
    
    /**
     * Read public key from chip
     */
    func readPublicKey(completion: @escaping (Result<String, Error>) -> Void) {
        // First, select applet
        let selectCommand = APDUCommands.selectApplet()
        
        sendAPDU(selectCommand) { [weak self] result in
            switch result {
            case .success(let selectResponse):
                guard let selectAPDU = APDUResponse(rawResponse: selectResponse),
                      selectAPDU.isSuccess else {
                    completion(.failure(NFCError(.tagCommandApplicationError)))
                    return
                }
                
                // Now get key info
                let getKeyInfoCommand = APDUCommands.getKeyInfo()
                self?.sendAPDU(getKeyInfoCommand) { result in
                    switch result {
                    case .success(let keyResponse):
                        guard let keyAPDU = APDUResponse(rawResponse: keyResponse),
                              keyAPDU.isSuccess,
                              let publicKey = APDUHandler.parsePublicKey(from: keyAPDU.data) else {
                            completion(.failure(NFCError(.tagResponseError)))
                            return
                        }
                        completion(.success(publicKey))
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /**
     * Sign message with chip
     */
    func signMessage(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        // First, select applet
        let selectCommand = APDUCommands.selectApplet()
        
        sendAPDU(selectCommand) { [weak self] result in
            switch result {
            case .success(let selectResponse):
                guard let selectAPDU = APDUResponse(rawResponse: selectResponse),
                      selectAPDU.isSuccess else {
                    completion(.failure(NFCError(.tagCommandApplicationError)))
                    return
                }
                
                // Now generate signature
                let signCommand = APDUCommands.generateSignature(messageHash: messageHash)
                self?.sendAPDU(signCommand) { result in
                    switch result {
                    case .success(let signResponse):
                        guard let signAPDU = APDUResponse(rawResponse: signResponse),
                              signAPDU.isSuccess,
                              let signature = APDUHandler.parseSignature(from: signAPDU.data) else {
                            completion(.failure(NFCError(.tagResponseError)))
                            return
                        }
                        completion(.success((r: signature.r, s: signature.s, recoveryId: signature.recoveryId)))
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
