/**
 * NFCISO7816TagReaderSession Delegate
 * Handles NFC tag detection and communication
 */

import Foundation
import CoreNFC

protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReceivePublicKey publicKey: String)
    func nfcService(_ service: NFCService, didReceiveSignature r: String, s: String, recoveryId: Int)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

class NFCSessionDelegate: NSObject, NFCISO7816TagReaderSessionDelegate {
    weak var service: NFCService?
    
    init(service: NFCService) {
        self.service = service
        super.init()
    }
    
    func tagReaderSession(_ session: NFCISO7816TagReaderSession, didDetect tags: [NFCISO7816Tag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        
            session.connect(to: tag) { [weak self] (error: Error?) in
            guard let self = self, let service = self.service else { return }
            
            if let error = error {
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                service.delegate?.nfcService(service, didFailWithError: error)
                return
            }
            
            // Tag connected, notify service
            service.tagConnected = tag
        }
    }
    
    func tagReaderSession(_ session: NFCISO7816TagReaderSession, didInvalidateWithError error: Error) {
        // Session invalidated (user cancelled, error, etc.)
        service?.sessionInvalidated(error: error)
    }
    
    // This method is called when user interaction is required
    func tagReaderSessionDidBecomeActive(_ session: NFCISO7816TagReaderSession) {
        // Session became active - can display UI if needed
    }
}
