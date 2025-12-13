/*
 MIT License
 
 Copyright (c) 2020 Infineon Technologies AG
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation
import CoreNFC

/// Helper class that manages the NFC card detection events
class NFCHelper: NSObject, NFCTagReaderSessionDelegate {
    let TAG: String = "NFCHelper"
    
    /// Background queue for NFC delegate callbacks (per Apple best practices)
    private let nfcQueue = DispatchQueue(label: "com.stellarmerch.nfc", qos: .userInitiated)
    
    /// Stores the reader session handle
    var reader_session: NFCTagReaderSession?
    /// Event handler which is called when the tag detection action is completed
    var OnTagEvent: ((Bool, NFCISO7816Tag?, NFCTagReaderSession?, String?) -> ())?

    /// Event handler for NDEF reading operations
    var OnNDEFEvent: ((Bool, String?, String?) -> ())?
    
    /// Timeout timer for 60-second session limit
    private var timeoutTimer: Timer?
    
    /// Maximum session duration (60 seconds per Apple's limit)
    private let maxSessionDuration: TimeInterval = 60.0
    
    // MARK: - NFC Reader Session Events
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print(TAG + ": ReaderSession: Active")
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print(TAG + ": ReaderSession: Invalidated")
        
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Clear session reference
        reader_session = nil
        
        guard let OnTagEvent = OnTagEvent else {
            return
        }
        
        // Comprehensive error handling per Apple best practices
        if let readerError = error as? NFCReaderError {
            let errorCode = readerError.code
            print(TAG + ": ReaderSession: Error code: \(errorCode.rawValue)")
            
            // Handle different error cases
            switch errorCode {
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                // Success case - tag was read successfully
                print(TAG + ": ReaderSession: Tag read successfully")
                return
                
            case .readerSessionInvalidationErrorUserCanceled:
                // User canceled - not an error
                print(TAG + ": ReaderSession: User canceled")
                return
                
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                // Session terminated unexpectedly
                print(TAG + ": ReaderSession: Session terminated unexpectedly")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session ended unexpectedly. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSystemIsBusy:
                // System is busy
                print(TAG + ": ReaderSession: System is busy")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC system is busy. Please try again.")
                }
                
            case .readerSessionInvalidationErrorSessionTimeout:
                // Session timeout (60 seconds)
                print(TAG + ": ReaderSession: Session timeout")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC session timed out. Please try again.")
                }
                
            default:
                // Other errors
                print(TAG + ": ReaderSession: Unknown error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    OnTagEvent(false, nil, nil, "NFC error: \(error.localizedDescription)")
                }
            }
        } else {
            // Non-NFCReaderError
            print(TAG + ": ReaderSession: Non-NFC error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                OnTagEvent(false, nil, nil, error.localizedDescription)
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print(TAG + ": ReaderSession: Tag detected")

        // Cancel timeout timer since we detected a tag
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        if tags.count > 1 {
            print(TAG + ": ReaderSession: Multiple tags found")
            session.alertMessage = "Multiple tags found. Please use only one tag."
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "Multiple tags found. Please use only one tag.")
                }
                if let OnNDEFEvent = self.OnNDEFEvent {
                    OnNDEFEvent(false, nil, "Multiple tags found. Please use only one tag.")
                }
            }
            EndSession()
            return
        }

        guard let firstTag = tags.first else {
            print(TAG + ": ReaderSession: No tags in array")
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "No tag detected")
                }
                if let OnNDEFEvent = self.OnNDEFEvent {
                    OnNDEFEvent(false, nil, "No tag detected")
                }
            }
            return
        }

        if case let NFCTag.iso7816(tag) = firstTag {
            session.connect(to: firstTag) { [weak self] (error: Error?) in
                guard let self = self else { return }
                if let error = error {
                    print(self.TAG + ": ReaderSession: Connection error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        if let OnTagEvent = self.OnTagEvent {
                            OnTagEvent(false, nil, nil, "Failed to connect to tag: \(error.localizedDescription)")
                        }
                        if let OnNDEFEvent = self.OnNDEFEvent {
                            OnNDEFEvent(false, nil, "Failed to connect to tag: \(error.localizedDescription)")
                        }
                    }
                } else {
                    print(self.TAG + ": ReaderSession: Tag connected successfully")

                    // Check which operation we're doing
                    if let OnNDEFEvent = self.OnNDEFEvent {
                        // NDEF reading operation
                        Task {
                            do {
                                let ndefUrl = try await self.readNDEFUrl(tag: tag, session: session)
                                DispatchQueue.main.async {
                                    OnNDEFEvent(true, ndefUrl, nil)
                                }
                            } catch {
                                DispatchQueue.main.async {
                                    OnNDEFEvent(false, nil, error.localizedDescription)
                                }
                            }
                        }
                    } else if let OnTagEvent = self.OnTagEvent {
                        // APDU operation
                        DispatchQueue.main.async {
                            OnTagEvent(true, tag, session, nil)
                        }
                    }
                }
            }
        } else {
            print(TAG + ": ReaderSession: Tag is not ISO7816 compatible")
            session.alertMessage = "Tag is not compatible"
            DispatchQueue.main.async {
                if let OnTagEvent = self.OnTagEvent {
                    OnTagEvent(false, nil, nil, "Tag is not ISO7816 compatible")
                }
                if let OnNDEFEvent = self.OnNDEFEvent {
                    OnNDEFEvent(false, nil, "Tag is not ISO7816 compatible")
                }
            }
        EndSession()
    }
}
    
    // MARK: - Helper methods
    /// Checks if the NFC reader is supported by this device
    /// - Returns: Flag indicating true if NFC reader is supported
    func IsNFCReaderAvailable() -> Bool{
        return NFCTagReaderSession.readingAvailable
    }
    
    /// Begins the ISO14443 reader session
    func BeginSession() {
        // Check if device supports NFC reading
        guard IsNFCReaderAvailable() else {
            print(TAG + ": ReaderSession: NFC not available on this device")
            return
        }
        
        // Prevent multiple active sessions (Apple best practice)
        if reader_session != nil {
            print(TAG + ": ReaderSession: Session already active, invalidating previous session")
            EndSession()
        }
        
        // Create session with background queue (Apple best practice)
        reader_session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: nfcQueue
        )
        
        reader_session?.alertMessage = "Hold your device near the NFC chip"
        reader_session?.begin()
        
        print(TAG + ": ReaderSession: Begin")
        
        // Set up timeout timer for 60-second limit (Apple's maximum)
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maxSessionDuration, repeats: false) { [weak self] _ in
            guard let self = self, let session = self.reader_session else { return }
            print(self.TAG + ": ReaderSession: Timeout reached (60 seconds)")
            session.invalidate(errorMessage: "Session timed out. Please try again.")
        }
    }
    
    /// Invalidates the NFC reader session
    func EndSession(){
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        reader_session?.invalidate()
        reader_session = nil

        print(TAG + ": ReaderSession: End")
    }

    // MARK: - NDEF Operations

    /// NDEF Application ID
    private let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// NDEF File ID
    private let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]

    /// Read NDEF URL from chip using APDU commands
    func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        print(TAG + ": Reading NDEF URL...")

        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                print(TAG + ": Failed to create SELECT NDEF Application APDU")
                return nil
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)

            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                print(TAG + ": Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)")
                return nil
            }
            print(TAG + ": NDEF Application selected")

            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                print(TAG + ": Failed to create SELECT NDEF File APDU")
                return nil
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)

            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                print(TAG + ": Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)")
                return nil
            }
            print(TAG + ": NDEF File selected")

            // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
            guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
                print(TAG + ": Failed to create READ NLEN APDU")
                return nil
            }
            let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)

            guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else {
                print(TAG + ": Failed to read NLEN: \(readNlenSW1) \(readNlenSW2)")
                return nil
            }

            let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
            if nlen == 0 {
                print(TAG + ": No NDEF data (NLEN = 0)")
                return nil
            }

            print(TAG + ": NLEN = \(nlen) bytes")

            // Step 4: Read actual NDEF data (starting from offset 2)
            var ndefData = Data()
            var currentOffset: UInt16 = 2
            let maxReadLength: UInt8 = 255 - 2

            while ndefData.count < Int(nlen) {
                let bytesToRead = min(Int(nlen) - ndefData.count, Int(maxReadLength))

                guard let readBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xB0,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(bytesToRead)
                ])) else {
                    print(TAG + ": Failed to create READ BINARY APDU")
                    return nil
                }

                let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)

                guard readSW1 == 0x90 && readSW2 == 0x00 else {
                    print(TAG + ": Failed to read NDEF data chunk: \(readSW1) \(readSW2)")
                    return nil
                }

                ndefData.append(readData)
                currentOffset += UInt16(bytesToRead)
            }

            // Parse the NDEF URL
            return parseNDEFUrl(from: ndefData)

        } catch {
            print(TAG + ": Error reading NDEF: \(error)")
            throw error
        }
    }

    /// Parse NDEF URL record from raw data
    private func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 5 else {
            print(TAG + ": NDEF data too short")
            return nil
        }

        // Parse NDEF record
        let recordHeader = data[0]
        let typeLength = data[1]

        // Check if it's a URL record (type length should be 1 for 'U')
        guard typeLength == 1 else {
            print(TAG + ": Not a URL record (typeLength=\(typeLength))")
            return nil
        }

        // Calculate payload offset
        var payloadOffset = 3 // Default for short record without ID
        var payloadLength = Int(data[2])

        if recordHeader & 0x10 != 0 {
            // Short record
            if recordHeader & 0x08 != 0 {
                // Has ID length
                payloadOffset = 4
            }
        } else {
            // Long record
            if data.count >= 7 {
                payloadLength = Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
                payloadOffset = recordHeader & 0x08 != 0 ? 7 : 5
            } else {
                return nil
            }
        }

        // Check type (should be 0x55 for 'U')
        guard payloadOffset < data.count && data[payloadOffset] == 0x55 else {
            print(TAG + ": Not a URL record (type != 0x55)")
            return nil
        }

        let payloadStart = payloadOffset + 1
        guard payloadStart < data.count else {
            print(TAG + ": No payload data")
            return nil
        }

        let payload = data.subdata(in: payloadStart..<min(data.count, payloadStart + payloadLength))

        // Parse URL prefix
        guard let prefixByte = payload.first else {
            print(TAG + ": Empty payload")
            return nil
        }

        let prefixes: [UInt8: String] = [
            0x00: "",
            0x01: "http://www.",
            0x02: "https://www.",
            0x03: "http://",
            0x04: "https://"
        ]

        guard let prefix = prefixes[prefixByte] else {
            print(TAG + ": Unknown URL prefix: 0x\(String(format: "%02X", prefixByte))")
            return nil
        }

        let urlData = payload.dropFirst()
        guard let urlString = String(data: urlData, encoding: .utf8) else {
            print(TAG + ": Invalid UTF-8 in URL")
            return nil
        }

        let fullUrl = prefix + urlString
        print(TAG + ": Successfully parsed NDEF URL: \(fullUrl)")
        return fullUrl
    }
}
