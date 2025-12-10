/**
 * NFCTagReaderSession Delegate
 * Handles NFC tag detection and communication for ISO 7816 tags (SECORA chips)
 */

import Foundation
import CoreNFC

protocol NFCServiceDelegate: AnyObject {
    func nfcService(_ service: NFCService, didReceivePublicKey publicKey: String)
    func nfcService(_ service: NFCService, didReceiveSignature r: String, s: String, recoveryId: Int)
    func nfcService(_ service: NFCService, didFailWithError error: Error)
}

class NFCSessionDelegate: NSObject, NFCTagReaderSessionDelegate {
    weak var service: NFCService?
    
    init(service: NFCService) {
        self.service = service
        super.init()
    }
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session became active - iOS NFC scan UI should now be visible
        print("NFC: ✅ Session became active - iOS NFC scan UI should now be visible!")
        // Update alert message to guide user
        session.alertMessage = "Hold your device near the NFC chip"
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("NFC: Tag detected, count: \(tags.count)")
        
        guard let firstTag = tags.first else {
            print("NFC Error: No tag in array")
            session.invalidate(errorMessage: "No tag detected")
            return
        }
        
        print("NFC: Tag type: \(firstTag)")
        
        // Only handle ISO 7816 tags (SECORA chips)
        guard case .iso7816(let iso7816Tag) = firstTag else {
            print("NFC Error: Unsupported tag type. Expected ISO 7816, got: \(firstTag)")
            session.invalidate(errorMessage: "Unsupported tag type. SECORA chips use ISO 7816.")
            return
        }
        
        print("NFC: Connecting to ISO 7816 tag...")
        session.connect(to: firstTag) { [weak self] (error: Error?) in
            guard let self = self, let service = self.service else {
                print("NFC Error: Service deallocated during connection")
                return
            }
            
            if let error = error {
                print("NFC Error: Connection failed: \(error.localizedDescription)")
                session.invalidate(errorMessage: "Connection failed: \(error.localizedDescription)")
                service.delegate?.nfcService(service, didFailWithError: error)
                return
            }
            
            print("NFC: Tag connected successfully")
            // Tag connected, notify service with ISO 7816 tag
            service.tagConnected = iso7816Tag
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // Session invalidated (user cancelled, error, etc.)
        if let nfcError = error as? NFCReaderError {
            let codeName: String
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                codeName = "UserCanceled"
            case .readerSessionInvalidationErrorSessionTimeout:
                codeName = "SessionTimeout"
            case .readerSessionInvalidationErrorSystemIsBusy:
                codeName = "SystemIsBusy"
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                codeName = "FirstNDEFTagRead"
            @unknown default:
                codeName = "Unknown(\(nfcError.code.rawValue))"
            }
            print("NFC: ❌ Session invalidated - code: \(codeName) (\(nfcError.code.rawValue)), message: \(error.localizedDescription)")
        } else {
            print("NFC: ❌ Session invalidated - error: \(error.localizedDescription)")
        }
        service?.sessionInvalidated(error: error)
    }
}
