/**
 * APDU Command Definitions for SECORA Blockchain Chip
 * Based on Infineon SECORA Blockchain specifications and blocksec2go implementation
 */

import Foundation

struct APDUCommands {
    // AID for SECORA Blockchain applet
    static let AID: [UInt8] = [
        0xD2, 0x76, 0x00, 0x00, 0x04, 0x15, 0x02, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00
    ]
    
    /**
     * SELECT applet command
     * 00A40400 0F D276000004150200000000010000
     */
    static func selectApplet() -> Data {
        var command = Data()
        command.append(0x00) // CLA
        command.append(0xA4) // INS: SELECT
        command.append(0x04) // P1: Select by name
        command.append(0x00) // P2
        command.append(UInt8(AID.count)) // Lc: Length of AID
        command.append(contentsOf: AID) // Data: AID
        command.append(0x00) // Le: Expected response length (0 = max)
        return command
    }
    
    /**
     * GET_KEY_INFO command
     * Returns public key from chip
     * Format: 80 50 00 00 01 00
     */
    static func getKeyInfo(keyIndex: UInt8 = 1) -> Data {
        var command = Data()
        command.append(0x80) // CLA
        command.append(0x50) // INS: GET_KEY_INFO
        command.append(0x00) // P1
        command.append(0x00) // P2
        command.append(0x01) // Lc: Length of data
        command.append(keyIndex) // Data: Key index (1)
        command.append(0x00) // Le: Expected response length (0 = max)
        return command
    }
    
    /**
     * GENERATE_SIGNATURE command
     * Signs a message hash
     * Format: 80 51 00 00 20 <32-byte hash> 00
     */
    static func generateSignature(keyIndex: UInt8 = 1, messageHash: Data) -> Data {
        guard messageHash.count == 32 else {
            fatalError("Message hash must be exactly 32 bytes")
        }
        
        var command = Data()
        command.append(0x80) // CLA
        command.append(0x51) // INS: GENERATE_SIGNATURE
        command.append(0x00) // P1
        command.append(0x00) // P2
        command.append(0x21) // Lc: Length of data (1 byte key index + 32 bytes hash)
        command.append(keyIndex) // Data: Key index (1)
        command.append(messageHash) // Data: 32-byte message hash
        command.append(0x00) // Le: Expected response length (0 = max)
        return command
    }
}
