import Foundation
import CoreNFC

/// Utility class for NDEF operations on NFC chips
final class NDEFReader {
    /// NDEF Application ID
    private static let NDEF_AID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]
    
    /// NDEF File ID
    private static let NDEF_FILE_ID: [UInt8] = [0xE1, 0x04]
    
    /// Read NDEF URL from chip using APDU commands
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    /// - Returns: NDEF URL string if found, nil otherwise
    /// - Throws: AppError if reading fails
    static func readNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession) async throws -> String? {
        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF Application APDU"))
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)
            
            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)"))
            }
            
            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)
            
            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            
            // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
            guard let readNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xB0, 0x00, 0x00, 0x02])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create READ NLEN APDU"))
            }
            let (readNlenData, readNlenSW1, readNlenSW2) = try await tag.sendCommand(apdu: readNlenAPDU)
            
            guard readNlenSW1 == 0x90 && readNlenSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to read NLEN: \(readNlenSW1) \(readNlenSW2)"))
            }
            
            guard readNlenData.count >= 2 else {
                throw AppError.nfc(.readWriteFailed("Invalid NLEN data length: expected 2 bytes, got \(readNlenData.count)"))
            }
            
            let nlen = UInt16(readNlenData[0]) << 8 | UInt16(readNlenData[1])
            if nlen == 0 {
                return nil
            }
            
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
                    throw AppError.nfc(.readWriteFailed("Failed to create READ BINARY APDU"))
                }
                
                let (readData, readSW1, readSW2) = try await tag.sendCommand(apdu: readBinaryAPDU)
                
                guard readSW1 == 0x90 && readSW2 == 0x00 else {
                    throw AppError.nfc(.readWriteFailed("Failed to read NDEF data chunk: \(readSW1) \(readSW2)"))
                }
                
                ndefData.append(readData)
                currentOffset += UInt16(bytesToRead)
            }
            
            // Parse the NDEF URL
            return parseNDEFUrl(from: ndefData)
            
        } catch {
            throw error
        }
    }
    
    /// Write NDEF URL to chip
    /// - Parameters:
    ///   - tag: NFCISO7816Tag for chip communication
    ///   - session: NFCTagReaderSession for session management
    ///   - url: URL string to write
    /// - Throws: AppError if writing fails
    static func writeNDEFUrl(tag: NFCISO7816Tag, session: NFCTagReaderSession, url: String) async throws {
        // Convert URL to NDEF record bytes
        guard let ndefBytes = createNDEFRecord(for: url) else {
            throw AppError.nfc(.readWriteFailed("Failed to create NDEF record"))
        }
        
        do {
            // Step 1: Select NDEF Application
            guard let selectAppAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x04, 0x00] + [UInt8(NDEF_AID.count)] + NDEF_AID + [0x00])) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF Application APDU"))
            }
            let (_, selectAppSW1, selectAppSW2) = try await tag.sendCommand(apdu: selectAppAPDU)
            
            guard selectAppSW1 == 0x90 && selectAppSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF application: \(selectAppSW1) \(selectAppSW2)"))
            }
            
            // Step 2: Select NDEF File
            guard let selectFileAPDU = NFCISO7816APDU(data: Data([0x00, 0xA4, 0x00, 0x0C, 0x02] + NDEF_FILE_ID)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create SELECT NDEF File APDU"))
            }
            let (_, selectFileSW1, selectFileSW2) = try await tag.sendCommand(apdu: selectFileAPDU)
            
            guard selectFileSW1 == 0x90 && selectFileSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to select NDEF file: \(selectFileSW1) \(selectFileSW2)"))
            }
            
            // Step 3: Write NLEN (NDEF message length)
            let nlen = UInt16(ndefBytes.count)
            let nlenBytes = [UInt8((nlen >> 8) & 0xFF), UInt8(nlen & 0xFF)]
            guard let writeNlenAPDU = NFCISO7816APDU(data: Data([0x00, 0xD6, 0x00, 0x00, 0x02] + nlenBytes)) else {
                throw AppError.nfc(.readWriteFailed("Failed to create WRITE NLEN APDU"))
            }
            let (_, writeNlenSW1, writeNlenSW2) = try await tag.sendCommand(apdu: writeNlenAPDU)
            
            guard writeNlenSW1 == 0x90 && writeNlenSW2 == 0x00 else {
                throw AppError.nfc(.readWriteFailed("Failed to write NLEN: \(writeNlenSW1) \(writeNlenSW2)"))
            }
            
            // Step 4: Write NDEF data (starting from offset 2)
            var currentOffset: UInt16 = 2
            let maxWriteLength: UInt8 = 255 - 2
            
            for chunkStart in stride(from: 0, to: ndefBytes.count, by: Int(maxWriteLength)) {
                let chunkEnd = min(chunkStart + Int(maxWriteLength), ndefBytes.count)
                let chunk = ndefBytes[chunkStart..<chunkEnd]
                
                guard let updateBinaryAPDU = NFCISO7816APDU(data: Data([
                    0x00, 0xD6,
                    UInt8((currentOffset >> 8) & 0xFF),
                    UInt8(currentOffset & 0xFF),
                    UInt8(chunk.count)
                ] + Array(chunk))) else {
                    throw AppError.nfc(.readWriteFailed("Failed to create UPDATE BINARY APDU"))
                }
                
                let (_, writeSW1, writeSW2) = try await tag.sendCommand(apdu: updateBinaryAPDU)
                
                guard writeSW1 == 0x90 && writeSW2 == 0x00 else {
                    throw AppError.nfc(.readWriteFailed("Failed to write NDEF chunk at offset \(currentOffset): \(writeSW1) \(writeSW2)"))
                }
                
                currentOffset += UInt16(chunk.count)
            }
        } catch {
            throw error
        }
    }
    
    /// Parse NDEF URL record from raw data
    /// - Parameter data: Raw NDEF data
    /// - Returns: Parsed URL string if valid, nil otherwise
    static func parseNDEFUrl(from data: Data) -> String? {
        guard data.count >= 7 else {
            return nil
        }
        
        // Parse NDEF record - try both parsing methods
        // Method 1: Simple format (used in ClaimService, TransferService)
        if let url = parseNDEFUrlSimple(from: data) {
            return url
        }
        
        // Method 2: Complex format (used in NFCHelper)
        return parseNDEFUrlComplex(from: data)
    }
    
    /// Simple NDEF URL parsing (for standard short records)
    private static func parseNDEFUrlSimple(from data: Data) -> String? {
        // Ensure we have at least 3 bytes for flags, typeLength, and payloadLength
        guard data.count >= 3 else {
            return nil
        }
        
        let _ = data[0] // flags
        let typeLength = data[1]
        let payloadLength = data[2]
        let typeStart = 3
        let payloadStart = typeStart + Int(typeLength)
        
        guard data.count >= payloadStart + Int(payloadLength) else {
            return nil
        }
        
        let typeData = data.subdata(in: typeStart..<payloadStart)
        let payloadData = data.subdata(in: payloadStart..<payloadStart + Int(payloadLength))
        
        // Check if this is a URI record
        guard typeData.count == 1 && typeData[0] == 0x55 else {
            return nil
        }
        
        // Parse URI payload
        guard payloadData.count >= 1 else {
            return nil
        }
        
        let uriIdentifierCode = payloadData[0]
        let uriData = payloadData.subdata(in: 1..<payloadData.count)
        
        // Get prefix from URI identifier code
        let prefix = getURIPrefix(for: uriIdentifierCode)
        
        guard let uriString = String(data: uriData, encoding: .utf8) else {
            return nil
        }
        
        return prefix + uriString
    }
    
    /// Complex NDEF URL parsing (handles short/long records)
    private static func parseNDEFUrlComplex(from data: Data) -> String? {
        guard data.count >= 5 else {
            return nil
        }
        
        let recordHeader = data[0]
        let typeLength = data[1]
        
        // Check if it's a URL record (type length should be 1 for 'U')
        guard typeLength == 1 else {
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
            guard data.count >= 7 else {
                return nil
            }
            payloadLength = Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
            payloadOffset = recordHeader & 0x08 != 0 ? 7 : 5
        }
        
        // Check type (should be 0x55 for 'U')
        guard payloadOffset < data.count && data[payloadOffset] == 0x55 else {
            return nil
        }
        
        let payloadStart = payloadOffset + 1
        guard payloadStart < data.count else {
            return nil
        }
        
        let payload = data.subdata(in: payloadStart..<min(data.count, payloadStart + payloadLength))
        
        // Parse URL prefix
        guard let prefixByte = payload.first else {
            return nil
        }
        
        let prefix = getURIPrefix(for: prefixByte)
        let urlData = payload.dropFirst()
        
        guard let urlString = String(data: urlData, encoding: .utf8) else {
            return nil
        }
        
        return prefix + urlString
    }
    
    /// Get URI prefix from identifier code
    private static func getURIPrefix(for code: UInt8) -> String {
        let uriPrefixes = [
            "", // 0x00: no prefix
            "http://www.", // 0x01
            "https://www.", // 0x02
            "http://", // 0x03
            "https://", // 0x04
            "tel:", // 0x05
            "mailto:", // 0x06
            "ftp://anonymous:anonymous@", // 0x07
            "ftp://ftp.", // 0x08
            "ftps://", // 0x09
            "sftp://", // 0x0A
            "smb://", // 0x0B
            "nfs://", // 0x0C
            "ftp://", // 0x0D
            "dav://", // 0x0E
            "news:", // 0x0F
            "telnet://", // 0x10
            "imap:", // 0x11
            "rtsp://", // 0x12
            "urn:", // 0x13
            "pop:", // 0x14
            "sip:", // 0x15
            "sips:", // 0x16
            "tftp:", // 0x17
            "btspp://", // 0x18
            "btl2cap://", // 0x19
            "btgoep://", // 0x1A
            "tcpobex://", // 0x1B
            "irdaobex://", // 0x1C
            "file://", // 0x1D
            "urn:epc:id:", // 0x1E
            "urn:epc:tag:", // 0x1F
            "urn:epc:pat:", // 0x20
            "urn:epc:raw:", // 0x21
            "urn:epc:", // 0x22
            "urn:nfc:" // 0x23
        ]
        
        if Int(code) < uriPrefixes.count {
            return uriPrefixes[Int(code)]
        }
        return ""
    }
    
    /// Create NDEF URI record from URL string
    /// - Parameter url: URL string to encode
    /// - Returns: NDEF record bytes
    static func createNDEFRecord(for url: String) -> Data? {
        guard let urlData = url.data(using: .utf8) else { return nil }
        
        // NDEF URI record format:
        // 0xD1 (MB=1, ME=1, CF=0, SR=1, IL=0, TNF=1) - URI record
        // 0x01 (Type length = 1)
        // Payload length (1 byte since SR=1)
        // 0x55 (Type = 'U' for URI)
        // Identifier code (0x00 = no prefix)
        // URI data
        
        let payloadLength = 1 + urlData.count // identifier code + url
        
        var record = Data()
        record.append(0xD1) // TNF=URI, SR=1, ME=1, MB=1
        record.append(0x01) // Type length
        record.append(UInt8(payloadLength)) // Payload length
        record.append(0x55) // Type 'U'
        record.append(0x00) // No URI prefix
        record.append(urlData)
        
        return record
    }
    
    /// Parse contract ID from NDEF URL
    /// Expected format: [protocol]://[domain]/[contractID]/[token_id] or [protocol]://[domain]/[contractID]
    /// - Parameter url: NDEF URL string
    /// - Returns: Contract ID if found and valid, nil otherwise
    static func parseContractIdFromNDEFUrl(_ url: String) -> String? {
        // Remove protocol if present
        var urlPath = url
        if urlPath.hasPrefix("http://") {
            urlPath = String(urlPath.dropFirst(7))
        } else if urlPath.hasPrefix("https://") {
            urlPath = String(urlPath.dropFirst(8))
        }
        
        // Split by '/' and expect contract ID as second component
        let components = urlPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else {
            return nil
        }
        
        let contractId = String(components[1])
        
        // Validate contract ID format (Stellar contract IDs are 56 characters, start with 'C')
        guard contractId.count == 56 && contractId.hasPrefix("C") else {
            return nil
        }
        
        return contractId
    }
}

