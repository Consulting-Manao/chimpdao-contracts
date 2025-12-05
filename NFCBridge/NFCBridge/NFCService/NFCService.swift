/**
 * NFC Service
 * Manages NFCISO7816TagReaderSession and APDU communication with SECORA chip
 */

import Foundation
import CoreNFC

class NFCService {
    weak var delegate: NFCServiceDelegate?
    
    private var session: NFCTagReaderSession?
    private var sessionDelegate: NFCSessionDelegate?
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
     * Uses NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags (SECORA chips)
     * MUST be called on main thread
     */
    func startSession() {
        // Ensure we're on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.startSession()
            }
            return
        }
        
        // Check if NFC is available - use NFCTagReaderSession.readingAvailable for ISO 7816 tags
        // NFCNDEFReaderSession.readingAvailable might not be the right check for ISO 7816
        
        // Check if running on simulator
        #if targetEnvironment(simulator)
        let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "NFC is not available on iOS Simulator. Please run on a physical device."])
        print("NFC Error: Running on simulator - NFC requires a physical device")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.nfcService(self, didFailWithError: error)
        }
        return
        #endif
        
        guard NFCTagReaderSession.readingAvailable else {
            var errorMessage = "NFC not available on this device. "
            errorMessage += "Possible causes:\n"
            errorMessage += "1. NFC is disabled in Settings\n"
            errorMessage += "2. Device doesn't support NFC\n"
            errorMessage += "3. App doesn't have NFC capability enabled\n"
            errorMessage += "4. Entitlements file not properly configured\n"
            errorMessage += "5. NFC Tag Reading requires a paid Apple Developer account (personal teams don't support this capability)"
            
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            print("NFC Error: NFC not available (NFCTagReaderSession.readingAvailable = false)")
            print("  - Check Settings > General > NFC is enabled")
            print("  - Verify app has NFC capability in Xcode project")
            print("  - Verify entitlements file is linked in project settings")
            print("  - Note: NFC Tag Reading requires a paid Apple Developer account")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        
        print("NFC: ✅ NFCTagReaderSession.readingAvailable = true")
        
        // Don't start a new session if one is already active
        if session != nil {
            print("NFC: Session already active")
            return
        }
        
        print("NFC: Starting session on main thread...")
        
        // Use NFCTagReaderSession with ISO 14443 polling for ISO 7816 tags
        // This will show the iOS NFC scan UI automatically
        // Keep reference to delegate to prevent deallocation
        sessionDelegate = NFCSessionDelegate(service: self)
        session = NFCTagReaderSession(
            pollingOption: .iso14443,
            delegate: sessionDelegate!,
            queue: DispatchQueue.main  // Use main queue for UI updates
        )
        
        guard let session = session else {
            print("NFC Error: Failed to create session - session is nil")
            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create NFC session"])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.nfcService(self, didFailWithError: error)
            }
            return
        }
        
        session.alertMessage = "Hold your device near the NFC chip"
        
        // Begin session - this should show the iOS NFC scan UI
        print("NFC: Calling session.begin() - this should show the iOS NFC scan UI")
        session.begin()
        print("NFC: session.begin() called - if scan UI doesn't appear, check:")
        print("  1. Device has NFC enabled in Settings")
        print("  2. App has NFC capability in entitlements")
        print("  3. Running on physical device (not simulator)")
        print("  4. Info.plist has correct NFC configuration")
    }
    
    /**
     * Stop NFC session
     */
    func stopSession() {
        session?.invalidate(errorMessage: "Session completed")
        session = nil
        sessionDelegate = nil
        currentTag = nil
        tagConnectedCallback = nil
    }
    
    /**
     * Session was invalidated
     */
    func sessionInvalidated(error: Error) {
        currentTag = nil
        session = nil
        sessionDelegate = nil
        tagConnectedCallback = nil
        
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
     * Start NFC session and wait for tag connection
     * Call this before sending APDU commands
     */
    func startSessionAndWaitForTag(completion: @escaping (Result<Void, Error>) -> Void) {
        // If tag already connected, return immediately
        if currentTag != nil {
            print("NFC: Tag already connected")
            completion(.success(()))
            return
        }
        
        print("NFC: Starting session and waiting for tag...")
        
        // Store completion for when tag connects
        tagConnectedCallback = { [weak self] in
            print("NFC: Tag connected callback triggered")
            if let self = self, self.currentTag != nil {
                print("NFC: ✅ Tag connection successful!")
                completion(.success(()))
            } else {
                print("NFC Error: Tag connection callback but tag is nil")
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tag connection failed - tag is nil"])))
            }
        }
        
        // Add timeout for tag connection (30 seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            if self.currentTag == nil && self.tagConnectedCallback != nil {
                print("NFC Error: Timeout waiting for tag connection")
                self.tagConnectedCallback = nil
                self.stopSession()
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for NFC tag. Please try again."])))
            }
        }
        
        startSession()
    }
    
    /**
     * Send APDU command to chip
     * Assumes session is already started and tag is connected
     */
    func sendAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No tag connected. Call startSessionAndWaitForTag() first."])))
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU after tag is connected
     */
    private func executeAPDU(_ apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let tag = currentTag else {
            completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Tag connection lost"])))
            return
        }
        
        executeAPDUOnTag(tag, apdu: apdu, completion: completion)
    }
    
    /**
     * Execute APDU on specific tag
     * According to Apple's CoreNFC documentation, completion handlers are called on the main queue
     */
    private func executeAPDUOnTag(_ tag: NFCISO7816Tag, apdu: Data, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let apduCommand = NFCISO7816APDU(data: apdu) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid APDU command"])))
            }
            return
        }
        
        print("NFC: Sending APDU command: \(apdu.map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        tag.sendCommand(
            apdu: apduCommand,
            completionHandler: { (response: Data, sw1: UInt8, sw2: UInt8, error: Error?) in
                // Completion handler is already called on main queue per Apple's documentation
                if let error = error {
                    print("NFC Error: APDU command failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                // Combine response data with status word
                var fullResponse = response
                fullResponse.append(sw1)
                fullResponse.append(sw2)
                
                let statusWord = UInt16(sw1) << 8 | UInt16(sw2)
                print("NFC: APDU response received, status: 0x\(String(format: "%04x", statusWord))")
                
                completion(.success(fullResponse))
            }
        )
    }
    
    /**
     * Read public key from chip
     */
    func readPublicKey(completion: @escaping (Result<String, Error>) -> Void) {
        print("NFC: readPublicKey() called")
        
        // Reset any existing tag connection
        currentTag = nil
        
        // Start session and wait for tag
        startSessionAndWaitForTag { [weak self] result in
            guard let self = self else {
                print("NFC Error: Service deallocated")
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success:
                print("NFC: Tag connected, starting to read public key...")
                // Tag connected, now send APDU commands
                self.readPublicKeyAfterConnection(completion: completion)
            case .failure(let error):
                print("NFC Error: Failed to connect tag: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /**
     * Read public key after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GET_KEY_INFO
     */
    private func readPublicKeyAfterConnection(completion: @escaping (Result<String, Error>) -> Void) {
        print("NFC: Starting public key read sequence...")
        
        // Step 1: Select applet (required before any other commands)
        let selectCommand = APDUCommands.selectApplet()
        print("NFC: Step 1 - Selecting applet...")
        
        sendAPDU(selectCommand) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success(let selectResponse):
                let selectAPDU = APDUResponse(rawResponse: selectResponse)
                guard let apdu = selectAPDU, apdu.isSuccess else {
                    let statusHex = selectAPDU != nil ? String(format: "0x%04x", selectAPDU!.statusWord) : "unknown"
                    print("NFC Error: SELECT applet failed with status: \(statusHex)")
                    let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to select applet. Status: \(statusHex)"])
                    completion(.failure(error))
                    self.stopSession()
                    return
                }
                
                print("NFC: ✅ Applet selected successfully")
                
                // Step 2: Get key info
                let getKeyInfoCommand = APDUCommands.getKeyInfo()
                print("NFC: Step 2 - Getting key info...")
                
                self.sendAPDU(getKeyInfoCommand) { result in
                    switch result {
                    case .success(let keyResponse):
                        let keyAPDU = APDUResponse(rawResponse: keyResponse)
                        guard let apdu = keyAPDU, apdu.isSuccess else {
                            let statusHex = keyAPDU != nil ? String(format: "0x%04x", keyAPDU!.statusWord) : "unknown"
                            print("NFC Error: GET_KEY_INFO failed with status: \(statusHex)")
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get key info. Status: \(statusHex)"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        guard let publicKey = APDUHandler.parsePublicKey(from: apdu.data) else {
                            print("NFC Error: Failed to parse public key from response")
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse public key"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        print("NFC: ✅ Public key read successfully: \(publicKey.prefix(20))...")
                        completion(.success(publicKey))
                        // Stop session after successful read
                        self.stopSession()
                        
                    case .failure(let error):
                        print("NFC Error: GET_KEY_INFO command failed: \(error.localizedDescription)")
                        completion(.failure(error))
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                print("NFC Error: SELECT applet command failed: \(error.localizedDescription)")
                completion(.failure(error))
                self.stopSession()
            }
        }
    }
    
    /**
     * Sign message with chip
     */
    func signMessage(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        // Start session and wait for tag
        startSessionAndWaitForTag { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                // Tag connected, now send APDU commands
                self.signMessageAfterConnection(messageHash: messageHash, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /**
     * Sign message after tag is connected
     * Follows Infineon SECORA reference implementation pattern:
     * 1. SELECT applet
     * 2. GENERATE_SIGNATURE
     */
    private func signMessageAfterConnection(messageHash: Data, completion: @escaping (Result<(r: String, s: String, recoveryId: Int), Error>) -> Void) {
        print("NFC: Starting signature generation sequence...")
        print("NFC: Message hash: \(messageHash.map { String(format: "%02x", $0) }.joined())")
        
        // Step 1: Select applet (required before any other commands)
        let selectCommand = APDUCommands.selectApplet()
        print("NFC: Step 1 - Selecting applet...")
        
        sendAPDU(selectCommand) { [weak self] result in
            guard let self = self else {
                completion(.failure(NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Service deallocated"])))
                return
            }
            
            switch result {
            case .success(let selectResponse):
                let selectAPDU = APDUResponse(rawResponse: selectResponse)
                guard let apdu = selectAPDU, apdu.isSuccess else {
                    let statusHex = selectAPDU != nil ? String(format: "0x%04x", selectAPDU!.statusWord) : "unknown"
                    print("NFC Error: SELECT applet failed with status: \(statusHex)")
                    let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to select applet. Status: \(statusHex)"])
                    completion(.failure(error))
                    self.stopSession()
                    return
                }
                
                print("NFC: ✅ Applet selected successfully")
                
                // Step 2: Generate signature
                let signCommand = APDUCommands.generateSignature(messageHash: messageHash)
                print("NFC: Step 2 - Generating signature...")
                
                self.sendAPDU(signCommand) { result in
                    switch result {
                    case .success(let signResponse):
                        let signAPDU = APDUResponse(rawResponse: signResponse)
                        guard let apdu = signAPDU, apdu.isSuccess else {
                            let statusHex = signAPDU != nil ? String(format: "0x%04x", signAPDU!.statusWord) : "unknown"
                            print("NFC Error: GENERATE_SIGNATURE failed with status: \(statusHex)")
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate signature. Status: \(statusHex)"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        guard let signature = APDUHandler.parseSignature(from: apdu.data) else {
                            print("NFC Error: Failed to parse signature from response")
                            let error = NSError(domain: "NFCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse signature"])
                            completion(.failure(error))
                            self.stopSession()
                            return
                        }
                        
                        print("NFC: ✅ Signature generated successfully")
                        print("NFC: r: \(signature.r.prefix(20))..., s: \(signature.s.prefix(20))..., recoveryId: \(signature.recoveryId)")
                        completion(.success((r: signature.r, s: signature.s, recoveryId: signature.recoveryId)))
                        // Stop session after successful signature
                        self.stopSession()
                        
                    case .failure(let error):
                        print("NFC Error: GENERATE_SIGNATURE command failed: \(error.localizedDescription)")
                        completion(.failure(error))
                        self.stopSession()
                    }
                }
                
            case .failure(let error):
                print("NFC Error: SELECT applet command failed: \(error.localizedDescription)")
                completion(.failure(error))
                self.stopSession()
            }
        }
    }
}
