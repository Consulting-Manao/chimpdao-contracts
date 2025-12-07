/**
 * NFC Server using nfc-pcsc for all APDU and NDEF operations
 * 
 * NOTE: This server MUST run with Node.js, not Bun, because @pokusew/pcsclite
 * is a native Node.js module that is incompatible with Bun's runtime.
 */

// Check if running under Bun and exit with helpful error
if (typeof Bun !== 'undefined') {
  console.error('❌ Error: This server must run with Node.js, not Bun.');
  console.error('   Native modules like @pokusew/pcsclite are not compatible with Bun.');
  console.error('   Please use: node index.js');
  console.error('   Or from the root: npm run nfc-server');
  process.exit(1);
}

import { WebSocketServer } from 'ws';
import { NFC, TAG_ISO_14443_3, TAG_ISO_14443_4 } from 'nfc-pcsc';

const PORT = 8080;

// Blockchain Security 2Go Application Identifier (AID)
// From blocksec2go Python library: D2760000041502000100000001 (13 bytes)
// Note: Different from Swift code which uses 15 bytes - Python library is the reference
const BLOCKCHAIN_AID = Buffer.from([
  0xD2, 0x76, 0x00, 0x00, 0x04, 0x15, 0x02, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x01
]);

class NFCServer {
  constructor() {
    this.wss = null;
    this.clients = new Set();
    this.chipPresent = false;
    this.nfc = null;
    this.currentReader = null;
    this.initNFC();
  }

  /**
   * Initialize nfc-pcsc for all NFC operations (APDU and NDEF)
   */
  initNFC() {
    this.nfc = new NFC();
    this.currentCard = null;
    this.cardReadyPromise = null;
    this.cardReadyResolve = null;
    
    this.nfc.on('reader', (reader) => {
      console.log(`NFC Reader detected: ${reader.reader.name}`);
      
      // Only use reader 2 (Identiv uTrust 4701 F Dual Interface Reader(2))
      // Skip other readers
      if (!reader.reader.name.includes('(2)')) {
        console.log(`Skipping reader "${reader.reader.name}" - only using reader (2)`);
        return;
      }
      
      console.log(`Using reader: ${reader.reader.name}`);
      this.currentReader = reader;
      
      // Disable auto-processing for ISO 14443-4 tags
      // We handle NDEF operations manually via block read/write, so we don't need
      // the automatic SELECT_APDU command that requires an AID
      // This allows both ISO 14443-3 and ISO 14443-4 tags to work for NDEF operations
      reader.autoProcessing = false;
      
      reader.on('card', async (card) => {
        try {
          console.log(`Card detected: ${card.type}, UID: ${card.uid || 'N/A'}`);
          // Store the card for NDEF operations
          this.currentCard = card;
          this.chipPresent = true;
          
          // With autoProcessing=false, we need to wait a bit for the connection to be fully established
          // This is especially important for ISO 14443-4 tags
          // Wait a bit longer to ensure connection is stable
          await new Promise(resolve => setTimeout(resolve, 200));
          
          // Verify card is still present after delay
          if (!this.currentCard || !this.chipPresent) {
            console.warn('Card was removed during initialization');
            return;
          }
          
          // Verify connection object exists
          if (!reader.connection) {
            console.warn('Connection not established, waiting a bit more...');
            await new Promise(resolve => setTimeout(resolve, 200));
          }
          
          // Resolve any pending card ready promises
          if (this.cardReadyResolve) {
            this.cardReadyResolve();
          }
          
          this.broadcastStatus();
        } catch (error) {
          console.error('Error handling card detection:', error);
          // Don't set chipPresent if there was an error
          this.currentCard = null;
          this.chipPresent = false;
        }
      });
      
      reader.on('card.off', (card) => {
        console.log('Card removed', card ? `(UID: ${card.uid || 'N/A'})` : '');
        this.currentCard = null;
        this.chipPresent = false;
        
        // Reject any pending card ready promises
        if (this.cardReadyPromise) {
          const { reject, timeout } = this.cardReadyPromise;
          clearTimeout(timeout);
          reject(new Error('Card was removed'));
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        
        this.broadcastStatus();
      });
      
      reader.on('error', (err) => {
        console.error('NFC Reader error:', err);
        // On reader error, clear card state as connection might be lost
        if (err.message && (err.message.includes('transmitting') || err.message.includes('connection'))) {
          console.warn('Reader connection error detected, clearing card state');
          this.currentCard = null;
          this.chipPresent = false;
          this.broadcastStatus();
        }
      });
    });
    
    this.nfc.on('error', (err) => {
      console.error('NFC error:', err);
    });
  }

  /**
   * Verify basic prerequisites (reader and card state)
   * Note: We don't check connection object as it may exist but be inactive
   * The actual read/write operations will reveal if connection is truly active
   */
  verifyConnection() {
    if (!this.currentReader) {
      return false;
    }
    if (!this.currentCard) {
      return false;
    }
    if (!this.chipPresent) {
      return false;
    }
    return true;
  }

  /**
   * Wait for card to be detected and ready for NDEF operations
   * Similar to how APDU operations wait for card connection
   * Based on nfc-pcsc best practices: card is automatically connected when card event fires
   */
  async waitForCardReady() {
    if (!this.currentReader) {
      throw new Error('No NFC reader available');
    }

    // If card is already present, verify it's still there
    if (this.currentCard && this.chipPresent) {
      // For ISO 14443-4 tags, wait a bit to ensure connection is stable
      // The connection might not be fully ready immediately
      if (this.currentCard.type === TAG_ISO_14443_4) {
        if (!this.verifyConnection()) {
          throw new Error('Connection lost, card needs to be re-presented');
        }
        // Small delay to ensure connection is stable before operations
        await new Promise(resolve => setTimeout(resolve, 100));
        // Verify again after delay
        if (!this.verifyConnection() || !this.currentReader.connection) {
          throw new Error('Connection lost during wait');
        }
        return;
      }
      
      // Small delay only for ISO 14443-3 tags that might need initialization
      await new Promise(resolve => setTimeout(resolve, 50));
      
      // Double-check card is still present after delay
      if (!this.currentCard || !this.chipPresent) {
        throw new Error('Card was removed during initialization');
      }
      
      return;
    }

    // Wait for card to be detected (with timeout)
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (this.cardReadyPromise && this.cardReadyPromise.resolve === resolve) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        reject(new Error('Timeout waiting for card. Please place the chip on the reader.'));
      }, 10000); // 10 second timeout

      this.cardReadyPromise = { resolve, reject, timeout };
      this.cardReadyResolve = () => {
        clearTimeout(timeout);
        if (this.cardReadyPromise && this.cardReadyPromise.resolve === resolve) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        resolve();
      };
    });
  }

  start() {
    this.wss = new WebSocketServer({ port: PORT });
    console.log(`WebSocket server started on port ${PORT}`);
    console.log('Using nfc-pcsc for all NFC operations (APDU and NDEF)');

    this.wss.on('connection', (ws) => {
      console.log('Client connected');
      this.clients.add(ws);

      // Send initial status
      this.checkChipStatus().then(() => this.sendStatus(ws));

      ws.on('message', async (message) => {
        try {
          const request = JSON.parse(message.toString());
          await this.handleRequest(ws, request);
        } catch (error) {
          this.sendError(ws, `Invalid request: ${error.message}`);
        }
      });

      ws.on('close', () => {
        console.log('Client disconnected');
        this.clients.delete(ws);
      });
    });

    // Don't poll - only check when operations are requested
    console.log('Server ready. Chip status will be checked on-demand.');
  }

  /**
   * Select Blockchain Security 2Go application
   * Must be called before any Blockchain APDU commands
   * APDU format from blocksec2go: 00 A4 04 00 [AID length] [AID] 00
   * AID: D2760000041502000100000001 (13 bytes)
   */
  async selectApplication() {
    if (!this.verifyConnection() || !this.currentReader.connection) {
      throw new Error('Connection not available');
    }
    
    // Wait a bit to ensure connection is stable
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify connection is still active after delay
    if (!this.currentReader.connection || !this.currentCard || !this.chipPresent) {
      throw new Error('Connection lost during initialization');
    }
    
    console.log(`selectApplication: Selecting Blockchain app (AID: ${BLOCKCHAIN_AID.toString('hex')})`);
    
    // SELECT Application APDU from blocksec2go: 00 A4 04 00 [AID length] [AID] 00
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xA4, 0x04, 0x00, BLOCKCHAIN_AID.length]),
      BLOCKCHAIN_AID,
      Buffer.from([0x00]) // Le: Expected response length (0 = max)
    ]);
    
    console.log(`selectApplication: Sending APDU: ${selectApp.toString('hex')}`);
    
    let response;
    try {
      response = await this.currentReader.transmit(selectApp, 40);
      console.log(`selectApplication: Response: ${response.toString('hex')}`);
    } catch (error) {
      console.error('selectApplication: Transmit failed:', error);
      // Clear card state on error to force re-detection
      this.clearCardState();
      throw new Error(`Failed to transmit SELECT command: ${error.message}`);
    }
    
    if (response.length < 2) {
      this.clearCardState();
      throw new Error(`Invalid response length: ${response.length}`);
    }
    
    const status = response.slice(-2);
    if (status[0] !== 0x90 || status[1] !== 0x00) {
      const statusHex = status.toString('hex');
      console.error(`selectApplication: Failed with status: ${statusHex}`);
      // Don't clear state on application selection failure - might be wrong AID or app not present
      throw new Error(`Failed to select Blockchain application: status=${statusHex}`);
    }
    
    console.log('selectApplication: Success');
    return true;
  }
  
  /**
   * Clear card state to force re-detection
   * Used when connection errors occur
   */
  clearCardState() {
    console.log('clearCardState: Clearing card state...');
    this.chipPresent = false;
    this.currentCard = null;
    // Don't disconnect - let the card re-detection handle it
  }

  /**
   * Get key information including public key and signature counters
   * APDU format: 00 16 [keyHandle] 00
   * Response format per official manual: [4 bytes global_counter] [4 bytes key_counter] [65 bytes public_key]
   * Reference: BlockchainSecurity2Go_UserManual.pdf section 4.3.2.3
   */
  async getKeyInfo(keyHandle = 1) {
    if (!this.verifyConnection() || !this.currentReader.connection) {
      throw new Error('Connection not available');
    }
    
    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }
    
    try {
      // Select application first
      await this.selectApplication();
      
      // Wait a bit for connection stability
      await new Promise(resolve => setTimeout(resolve, 50));
      
      // Verify connection is still active
      if (!this.currentReader.connection || !this.currentCard || !this.chipPresent) {
        throw new Error('Connection lost after SELECT application');
      }
      
      console.log(`getKeyInfo: Getting key info for handle ${keyHandle}`);
      
      // GET KEY INFO APDU from blocksec2go: 00 16 [keyHandle] 00
      // Format: CLA=0x00, INS=0x16, P1=keyHandle, P2=0x00, Le=0x00 (read max)
      const getKeyInfo = Buffer.from([
        0x00, // CLA
        0x16, // INS: GET_KEY_INFO
        keyHandle, // P1: Key handle
        0x00, // P2
        0x00 // Le: Expected response length (0 = max)
      ]);
      
      console.log(`getKeyInfo: Sending APDU: ${getKeyInfo.toString('hex')}`);
      
      const response = await this.currentReader.transmit(getKeyInfo, 255);
      console.log(`getKeyInfo: Response length: ${response.length}`);
      
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        const statusHex = response.slice(-2).toString('hex');
        console.error(`getKeyInfo: Failed with status: ${statusHex}`);
        throw new Error(`Failed to get key info: status=${statusHex}`);
      }
      
      // Parse response according to official Blockchain Security 2Go User Manual
      // Response format: [4 bytes global_counter] [4 bytes key_counter] [65 bytes public_key]
      // Reference: BlockchainSecurity2Go_UserManual.pdf section 4.3.2.3
      // Note: Format verified against manual - counters come first, then public key
      const data = response.slice(0, response.length - 2);
      
      if (data.length < 73) {
        throw new Error(`Invalid key info response: expected at least 73 bytes (4+4+65), got ${data.length}`);
      }
      
      // First 4 bytes: global signature counter (big endian, per official manual)
      const globalCounter = data.readUInt32BE(0);
      
      // Next 4 bytes: key-specific signature counter (big endian, per official manual)
      const keyCounter = data.readUInt32BE(4);
      
      // Remaining 65 bytes: uncompressed public key (0x04 + 64 bytes)
      const publicKey = data.slice(8, 73);
      
      if (publicKey.length !== 65) {
        throw new Error(`Invalid public key length: expected 65 bytes, got ${publicKey.length}`);
      }
      
      console.log(`getKeyInfo: Success, public key: ${publicKey.toString('hex').substring(0, 20)}..., counters: global=${globalCounter}, key=${keyCounter}`);
      
      return {
        publicKey: publicKey.toString('hex'),
        globalCounter,
        keyCounter
      };
    } catch (error) {
      console.error('getKeyInfo: Error:', error);
      // If it's a connection error, clear state to force re-detection
      if (error.message && (error.message.includes('unpowered') || error.message.includes('Connection') || error.message.includes('transmit'))) {
        this.clearCardState();
      }
      throw error;
    }
  }

  /**
   * Generate signature for a 32-byte message hash
   * APDU format: 00 18 [keyHandle] 00 + [32-byte hash]
   * Response format per official manual: [4 bytes global_counter] [4 bytes key_counter] [DER-encoded signature]
   * Reference: BlockchainSecurity2Go_UserManual.pdf section 4.3.2.4
   * Manual example confirms format: "000F423E 0001869E [signature]" = Global: 999998, Key: 99998
   */
  async generateSignature(keyHandle, messageDigest) {
    if (!this.verifyConnection() || !this.currentReader.connection) {
      throw new Error('Connection not available');
    }
    
    if (!messageDigest || messageDigest.length !== 32) {
      throw new Error('Message digest must be exactly 32 bytes');
    }
    
    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }
    
    try {
      // Select application first
      await this.selectApplication();
      
      // Wait a bit for connection stability
      await new Promise(resolve => setTimeout(resolve, 50));
      
      // Verify connection is still active
      if (!this.currentReader.connection || !this.currentCard || !this.chipPresent) {
        throw new Error('Connection lost after SELECT application');
      }
      
      console.log(`generateSignature: Generating signature for key handle ${keyHandle}`);
      
      // GENERATE SIGNATURE APDU from blocksec2go: 00 18 [keyHandle] 00 + [32-byte hash]
      // Format: CLA=0x00, INS=0x18, P1=keyHandle, P2=0x00, Lc=32, data=[32-byte hash], Le=0x00
      const generateSig = Buffer.concat([
        Buffer.from([
          0x00, // CLA
          0x18, // INS: GENERATE_SIGNATURE
          keyHandle, // P1: Key handle
          0x00, // P2
          0x20, // Lc: Length of data (32 bytes hash)
        ]),
        messageDigest, // Data: 32-byte message hash
        Buffer.from([0x00]) // Le: Expected response length (0 = max)
      ]);
      
      console.log(`generateSignature: Sending APDU: ${generateSig.toString('hex').substring(0, 20)}...`);
      
      const response = await this.currentReader.transmit(generateSig, 255);
      console.log(`generateSignature: Response length: ${response.length}`);
      
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        const statusHex = response.slice(-2).toString('hex');
        console.error(`generateSignature: Failed with status: ${statusHex}`);
        throw new Error(`Failed to generate signature: status=${statusHex}`);
      }
      
      // Parse response according to official Blockchain Security 2Go User Manual
      // Response format: [4 bytes global_counter] [4 bytes key_counter] [DER-encoded signature]
      // Reference: BlockchainSecurity2Go_UserManual.pdf section 4.3.2.4
      // Manual example: "000F423E 0001869E [signature]" = Global: 999998, Key: 99998
      // Format verified: counters are big endian, come before signature
      const data = response.slice(0, response.length - 2);
      
      if (data.length < 8) {
        throw new Error(`Invalid signature response: expected at least 8 bytes (counters), got ${data.length}`);
      }
      
      // First 4 bytes: global signature counter (big endian, per official manual example)
      const globalCounter = data.readUInt32BE(0);
      
      // Next 4 bytes: key-specific signature counter (big endian, per official manual example)
      const keyCounter = data.readUInt32BE(4);
      
      // Remaining bytes: DER-encoded signature
      const derSignature = data.slice(8);
      
      console.log(`generateSignature: Success, counters: global=${globalCounter}, key=${keyCounter}, signature length: ${derSignature.length}`);
      
      // Return just the DER signature (caller doesn't need counters for now, but we log them)
      return derSignature;
    } catch (error) {
      console.error('generateSignature: Error:', error);
      // If it's a connection error, clear state to force re-detection
      if (error.message && (error.message.includes('unpowered') || error.message.includes('Connection') || error.message.includes('transmit'))) {
        this.clearCardState();
      }
      throw error;
    }
  }

  async checkChipStatus() {
    // Use connection state instead of blocksec2go
    const wasPresent = this.chipPresent;
    
    // Check if we have a valid connection
    if (this.verifyConnection() && this.currentReader && this.currentReader.connection) {
      this.chipPresent = true;
      
      if (!wasPresent) {
        this.broadcastStatus();
      }
    } else {
      this.chipPresent = false;
      
      if (wasPresent) {
        this.broadcastStatus();
      }
    }
  }

  async handleRequest(ws, request) {
    const { type, data } = request;

    switch (type) {
      case 'status':
        await this.checkChipStatus(); // Check status when requested
        this.sendStatus(ws);
        break;

      case 'read-pubkey':
        await this.checkChipStatus(); // Ensure chip is present
        await this.readPublicKey(ws);
        break;

      case 'sign':
        await this.checkChipStatus(); // Ensure chip is present
        await this.signMessage(ws, data.messageDigest);
        break;

      case 'read-ndef':
        await this.checkChipStatus(); // Ensure chip is present
        await this.readNDEF(ws);
        break;

      case 'write-ndef':
        await this.checkChipStatus(); // Ensure chip is present
        await this.writeNDEF(ws, data.url);
        break;

      default:
        this.sendError(ws, `Unknown request type: ${type}`);
    }
  }

  async readPublicKey(ws) {
    if (!this.chipPresent) {
      this.sendError(ws, 'No chip present');
      return;
    }

    try {
      await this.waitForCardReady();
      
      const keyInfo = await this.getKeyInfo(1);
      
      ws.send(JSON.stringify({
        type: 'pubkey',
        success: true,
        data: {
          publicKey: keyInfo.publicKey,
          globalCounter: keyInfo.globalCounter,
          keyCounter: keyInfo.keyCounter
        }
      }));
    } catch (error) {
      console.error('Error reading public key:', error);
      this.sendError(ws, `Failed to read public key: ${error.message}`);
    }
  }

  async signMessage(ws, messageDigestHex) {
    if (!this.chipPresent) {
      this.sendError(ws, 'No chip present');
      return;
    }

    // Message digest must be 32 bytes (64 hex chars)
    if (!messageDigestHex || messageDigestHex.length !== 64) {
      this.sendError(ws, 'Invalid message digest (must be 32 bytes / 64 hex chars)');
      return;
    }

    try {
      await this.waitForCardReady();
      
      // Convert hex string to Buffer
      const messageDigest = Buffer.from(messageDigestHex, 'hex');
      
      if (messageDigest.length !== 32) {
        this.sendError(ws, 'Invalid message digest length');
        return;
      }
      
      // Generate signature using APDU
      const derSignature = await this.generateSignature(1, messageDigest);
      
      // Parse DER-encoded signature to extract r and s
      const derHex = derSignature.toString('hex');
      const { r, s } = this.parseDERSignature(derHex);
      
      // Recovery ID (v) - typically 1 for secp256k1
      const v = 1;
      const recoveryId = 1;

      ws.send(JSON.stringify({
        type: 'signature',
        success: true,
        data: { r, s, v, recoveryId }
      }));
    } catch (error) {
      console.error('Error signing message:', error);
      this.sendError(ws, `Failed to sign message: ${error.message}`);
    }
  }

  // Parse DER-encoded ECDSA signature
  parseDERSignature(derHex) {
    const der = Buffer.from(derHex, 'hex');
    let offset = 0;
    
    // 0x30: SEQUENCE
    if (der[offset++] !== 0x30) throw new Error('Invalid DER: not a SEQUENCE');
    offset++; // Skip total length
    
    // 0x02: INTEGER (r)
    if (der[offset++] !== 0x02) throw new Error('Invalid DER: r not an INTEGER');
    const rLength = der[offset++];
    const rBytes = der.slice(offset, offset + rLength);
    offset += rLength;
    
    // 0x02: INTEGER (s)
    if (der[offset++] !== 0x02) throw new Error('Invalid DER: s not an INTEGER');
    const sLength = der[offset++];
    let sBytes = der.slice(offset, offset + sLength);
    
    // Remove leading 0x00 if present (DER adds it when high bit is set)
    const rClean = rBytes[0] === 0x00 ? rBytes.slice(1) : rBytes;
    let sClean = sBytes[0] === 0x00 ? sBytes.slice(1) : sBytes;
    
    // Normalize s to low form (required by Stellar/Soroban)
    // secp256k1 curve order: n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    const CURVE_ORDER = Buffer.from('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141', 'hex');
    const HALF_CURVE_ORDER = Buffer.from('7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0', 'hex');
    
    // Convert to BigInt for comparison
    const sBigInt = BigInt('0x' + sClean.toString('hex'));
    const halfOrderBigInt = BigInt('0x' + HALF_CURVE_ORDER.toString('hex'));
    const orderBigInt = BigInt('0x' + CURVE_ORDER.toString('hex'));
    
    // If s > n/2, then s = n - s
    let sNormalized;
    if (sBigInt > halfOrderBigInt) {
      sNormalized = orderBigInt - sBigInt;
      sClean = Buffer.from(sNormalized.toString(16).padStart(64, '0'), 'hex');
    }
    
    // Pad to 32 bytes
    const rPadded = Buffer.alloc(32);
    rClean.copy(rPadded, 32 - rClean.length);
    const sPadded = Buffer.alloc(32);
    sClean.copy(sPadded, 32 - sClean.length);
    
    return {
      r: rPadded.toString('hex'),
      s: sPadded.toString('hex')
    };
  }

  sendStatus(ws) {
    const readerName = this.currentReader ? this.currentReader.reader.name : 'No reader';
    ws.send(JSON.stringify({
      type: 'status',
      data: {
        readerConnected: !!this.currentReader,
        chipPresent: this.chipPresent,
        readerName
      }
    }));
  }

  broadcastStatus() {
    const readerName = this.currentReader ? this.currentReader.reader.name : 'No reader';
    const status = JSON.stringify({
      type: 'status',
      data: {
        readerConnected: !!this.currentReader,
        chipPresent: this.chipPresent,
        readerName
      }
    });

    this.clients.forEach(client => {
      if (client.readyState === 1) {
        client.send(status);
      }
    });
  }

  /**
   * Read NDEF data from chip with retry logic
   * Based on nfc-pcsc best practices: operations should happen when card is present
   */
  async readNDEF(ws) {
    if (!this.currentReader) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
      return;
    }

    const maxRetries = 3;
    let lastError = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Wait for card to be detected and ready (similar to APDU operations)
        await this.waitForCardReady();

        // Verify basic prerequisites
        if (!this.verifyConnection()) {
          throw new Error('Card needs to be re-presented');
        }

        // Ensure connection is active before operation
        if (!this.currentReader.connection) {
          console.log('Connection not ready, waiting a bit more...');
          await new Promise(resolve => setTimeout(resolve, 200));
          if (!this.currentReader.connection) {
            throw new Error('Connection not established - card may need to be re-presented');
          }
        }

        let ndefData;
        
        // For ISO 14443-3 tags (Type 2), try block read first
        if (this.currentCard.type === TAG_ISO_14443_3) {
          try {
            console.log('Attempting block read for ISO 14443-3 tag...');
            ndefData = await this.currentReader.read(4, 16, 4);
            console.log('Block read successful');
          } catch (error) {
            console.log('Block read failed, trying APDU sequence...');
            ndefData = await this.readNDEFViaAPDU();
          }
        } else {
          // For ISO 14443-4 tags, use APDU sequence (block read doesn't work)
          ndefData = await this.readNDEFViaAPDU();
        }
        
        // Parse NDEF message
        const ndefUrl = this.parseNDEFUrl(ndefData);
        
        if (ndefUrl) {
          ws.send(JSON.stringify({
            type: 'ndef-read',
            success: true,
            data: { url: ndefUrl }
          }));
          return; // Success, exit retry loop
        } else {
          // No NDEF data found - this is not an error, just empty/invalid data
          ws.send(JSON.stringify({
            type: 'ndef-read',
            success: true,
            data: { url: null, message: 'No NDEF data found or invalid format' }
          }));
          return; // Exit retry loop (not a retryable error)
        }
        
      } catch (error) {
        lastError = error;
        const errorMessage = error.message || String(error);
        const isUnpowered = errorMessage.includes('unpowered') || 
                           (error.previous && error.previous.message && error.previous.message.includes('unpowered'));
        
        // If card is unpowered, clear state and wait for fresh detection
        if (isUnpowered) {
          console.log('Card is unpowered, clearing state and waiting for re-detection...');
          this.currentCard = null;
          this.chipPresent = false;
          
          // Wait for card to be re-detected (will trigger card event)
          if (attempt < maxRetries) {
            console.log(`Waiting for card re-detection (attempt ${attempt}/${maxRetries})...`);
            // Wait a bit for card event to fire
            await new Promise(resolve => setTimeout(resolve, 500));
            // Wait for card to be detected again
            await this.waitForCardReady();
            continue; // Retry with fresh card detection
          }
        }
        
        // Check if this is a retryable error
        const isRetryable = errorMessage.includes('transmitting') || 
                           errorMessage.includes('timeout') ||
                           errorMessage.includes('Card was removed') ||
                           errorMessage.includes('connection') ||
                           isUnpowered;
        
        if (!isRetryable || attempt === maxRetries) {
          // Non-retryable error or max retries reached
          console.error(`NDEF read error (attempt ${attempt}/${maxRetries}):`, error);
          this.sendError(ws, `Failed to read NDEF: ${errorMessage}`);
          return;
        }
        
        // Retryable error - wait before retrying
        console.warn(`NDEF read attempt ${attempt}/${maxRetries} failed, retrying...`, errorMessage);
        await new Promise(resolve => setTimeout(resolve, 200 * attempt));
      }
    }
  }

  /**
   * Parse NDEF URL from raw data
   */
  parseNDEFUrl(data) {
    try {
      if (!data || data.length === 0) {
        return null;
      }
      
      let ndefData = data;
      
      // Check if it's wrapped in TLV (starts with 0x03) - Type 2 tags
      if (data[0] === 0x03) {
        const length = data[1];
        if (length === 0) return null; // Empty NDEF message
        ndefData = data.slice(2, 2 + length);
      }
      // Otherwise, assume it's a raw NDEF record (from APDU) - starts with flags byte
      
      // Parse NDEF record
      if (ndefData.length < 5) return null;
      
      const recordHeader = ndefData[0];
      const typeLength = ndefData[1];
      const hasIdLength = (recordHeader & 0x08) !== 0; // IL flag (bit 3)
      
      // Payload length can be 1 byte (short record, SR=1) or 3 bytes (long record, SR=0)
      let payloadLength;
      let idLength = 0;
      let typeOffset;
      
      if (recordHeader & 0x10) {
        // Short record (SR=1): 1-byte payload length
        payloadLength = ndefData[2];
        typeOffset = 3;
        
        // If IL flag is set, there's an ID length byte
        if (hasIdLength) {
          idLength = ndefData[3];
          typeOffset = 4;
        }
      } else {
        // Long record (SR=0): 3-byte payload length
        payloadLength = (ndefData[2] << 16) | (ndefData[3] << 8) | ndefData[4];
        typeOffset = 5;
        
        // If IL flag is set, there's an ID length byte
        if (hasIdLength) {
          idLength = ndefData[5];
          typeOffset = 6;
        }
      }
      
      if (typeLength !== 1) return null; // Not a URL record
      
      const type = ndefData[typeOffset];
      if (type !== 0x55) return null; // Not a URL record (U = 0x55)
      
      const payloadOffset = typeOffset + typeLength + idLength;
      if (payloadOffset + payloadLength > ndefData.length) return null;
      
      const payload = ndefData.slice(payloadOffset, payloadOffset + payloadLength);
      
      // Parse URL prefix
      const prefix = payload[0];
      
      // URL prefix codes: https://www.ndef.org/resources/url-prefixes
      const prefixes = {
        0x00: '',
        0x01: 'http://www.',
        0x02: 'https://www.',
        0x03: 'http://',
        0x04: 'https://',
      };
      
      const url = (prefixes[prefix] || '') + payload.slice(1).toString('utf-8');
      return url;
    } catch (error) {
      console.error('NDEF parse error:', error);
      return null;
    }
  }

  /**
   * Read NDEF data via APDU sequence
   * Uses NDEF Application (AID: D2760000850101) - separate from Blockchain Application
   * This ensures NDEF and Blockchain operations don't interfere with each other
   * 
   * Sequence:
   * 1. SELECT NDEF Application
   * 2. SELECT NDEF File
   * 3. Read NLEN (2 bytes at offset 0) to get message length
   * 4. Read NDEF data (starting from offset 2) in chunks if needed
   */
  async readNDEFViaAPDU() {
    if (!this.verifyConnection() || !this.currentReader.connection) {
      throw new Error('Connection not available');
    }
    
    // Wait for connection stability (critical for ISO 14443-4 tags with autoProcessing=false)
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify connection is still active after delay
    if (!this.currentReader.connection || !this.currentCard || !this.chipPresent) {
      throw new Error('Connection lost during initialization');
    }
    
    // Step 1: Select NDEF Application
    const ndefAid = Buffer.from([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]);
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xA4, 0x04, 0x00, ndefAid.length]),
      ndefAid,
      Buffer.from([0x00]) // Le
    ]);
    
    let response;
    try {
      response = await this.currentReader.transmit(selectApp, 40);
    } catch (error) {
      if (error.message && error.message.includes('unpowered')) {
        this.clearCardState();
      }
      throw error;
    }
    
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to select NDEF application: status=${response.slice(-2).toString('hex')}`);
    }
    
    // Step 2: Select NDEF File
    const selectFile = Buffer.from([0x00, 0xA4, 0x00, 0x0C, 0x02, 0xE1, 0x04]);
    response = await this.currentReader.transmit(selectFile, 40);
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to select NDEF file: status=${response.slice(-2).toString('hex')}`);
    }
    
    // Step 3: Read NLEN (2 bytes at offset 0) to get NDEF message length
    const readNlen = Buffer.from([0x00, 0xB0, 0x00, 0x00, 0x02]);
    response = await this.currentReader.transmit(readNlen, 4);
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to read NLEN: status=${response.slice(-2).toString('hex')}`);
    }
    
    const nlen = response.readUInt16BE(0);
    if (nlen === 0) {
      return Buffer.alloc(0); // Empty NDEF message
    }
    
    // Step 4: Read actual NDEF data (starting from offset 2)
    // Read in chunks if message is larger than max read length
    const maxReadLength = 255 - 2; // Max data bytes + 2 status bytes
    let ndefDataBuffer = Buffer.alloc(0);
    let currentOffset = 2;
    
    while (ndefDataBuffer.length < nlen) {
      const bytesToRead = Math.min(nlen - ndefDataBuffer.length, maxReadLength);
      const readBinary = Buffer.from([
        0x00, // CLA
        0xB0, // INS: READ BINARY
        (currentOffset >> 8) & 0xFF, // P1: Offset high byte
        currentOffset & 0xFF, // P2: Offset low byte
        bytesToRead // Le: Number of bytes to read
      ]);
      
      response = await this.currentReader.transmit(readBinary, bytesToRead + 2);
      if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
        throw new Error(`Failed to read NDEF data chunk: status=${response.slice(-2).toString('hex')}`);
      }
      
      ndefDataBuffer = Buffer.concat([ndefDataBuffer, response.slice(0, -2)]);
      currentOffset += bytesToRead;
    }
    
    return ndefDataBuffer;
  }

  /**
   * Write NDEF data via APDU sequence (for ISO 14443-4 tags)
   * This is the only method that works for SECORA chips
   */
  /**
   * Write NDEF data via APDU sequence
   * Uses NDEF Application (AID: D2760000850101) - separate from Blockchain Application
   * This ensures NDEF and Blockchain operations don't interfere with each other
   * 
   * Sequence (verified working):
   * 1. SELECT NDEF Application
   * 2. SELECT NDEF File
   * 3. Write NDEF data at offset 2 using UPDATE BINARY (0xD6)
   * 4. Update NLEN with actual length using UPDATE BINARY (0xD6)
   * 
   * Note: Chip must be unlocked/writable. If chip is locked, operations will fail with 6985.
   */
  async writeNDEFViaAPDU(ndefMessage) {
    if (!this.verifyConnection() || !this.currentReader.connection) {
      throw new Error('Connection not available');
    }
    
    // Wait for connection stability (critical for ISO 14443-4 tags with autoProcessing=false)
    await new Promise(resolve => setTimeout(resolve, 100));
    
    // Verify connection is still active after delay
    if (!this.currentReader.connection || !this.currentCard || !this.chipPresent) {
      throw new Error('Connection lost during initialization');
    }
    
    // Step 1: Select NDEF Application
    const ndefAid = Buffer.from([0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]);
    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xA4, 0x04, 0x00, ndefAid.length]),
      ndefAid,
      Buffer.from([0x00]) // Le
    ]);
    
    let response;
    try {
      response = await this.currentReader.transmit(selectApp, 40);
    } catch (error) {
      console.error('writeNDEFViaAPDU: SELECT NDEF Application failed:', error);
      if (error.message && error.message.includes('unpowered')) {
        this.clearCardState();
      }
      throw error;
    }
    
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to select NDEF application: status=${response.slice(-2).toString('hex')}`);
    }
    
    // Step 2: Select NDEF File
    const selectFile = Buffer.from([0x00, 0xA4, 0x00, 0x0C, 0x02, 0xE1, 0x04]);
    response = await this.currentReader.transmit(selectFile, 40);
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to select NDEF file: status=${response.slice(-2).toString('hex')}`);
    }
    
    // Step 3: Write NDEF data at offset 2 (skip NLEN bytes at offset 0-1)
    // Use UPDATE BINARY (0xD6) - verified working approach
    console.log(`writeNDEFViaAPDU: Writing ${ndefMessage.length} bytes of NDEF data at offset 2...`);
    const writeData = Buffer.concat([
      Buffer.from([
        0x00, // CLA
        0xD6, // INS: UPDATE BINARY
        0x00, // P1: Offset high byte
        0x02, // P2: Offset low byte
        ndefMessage.length // Lc: Length of data
      ]),
      ndefMessage
    ]);
    
    response = await this.currentReader.transmit(writeData, 2);
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to write NDEF data: status=${response.slice(-2).toString('hex')}`);
    }
    
    // Step 4: Update NLEN with the actual NDEF message length
    const nlenBuffer = Buffer.alloc(2);
    nlenBuffer.writeUInt16BE(ndefMessage.length, 0);
    const updateNlen = Buffer.concat([
      Buffer.from([0x00, 0xD6, 0x00, 0x00, 0x02]),
      nlenBuffer
    ]);
    
    response = await this.currentReader.transmit(updateNlen, 2);
    if (response.length < 2 || response[response.length - 2] !== 0x90 || response[response.length - 1] !== 0x00) {
      throw new Error(`Failed to update NLEN: status=${response.slice(-2).toString('hex')}`);
    }
    
    console.log(`writeNDEFViaAPDU: Successfully wrote ${ndefMessage.length} bytes and updated NLEN`);
  }

  /**
   * Internal method to read NDEF data (for verification)
   * Returns URL string or null, throws on error
   */
  async readNDEFInternal() {
    if (!this.verifyConnection()) {
      throw new Error('Card needs to be re-presented');
    }
    
    let ndefData;
    
    // For ISO 14443-3 tags, try block read first
    if (this.currentCard.type === TAG_ISO_14443_3) {
      try {
        ndefData = await this.currentReader.read(4, 16, 4);
      } catch (error) {
        // Fall back to APDU if block read fails
        ndefData = await this.readNDEFViaAPDU();
      }
    } else {
      // For ISO 14443-4 tags, use APDU sequence
      ndefData = await this.readNDEFViaAPDU();
    }
    
    return this.parseNDEFUrl(ndefData);
  }

  /**
   * Write NDEF URL record to chip with retry logic and verification
   * Based on nfc-pcsc best practices: operations should happen when card is present
   */
  async writeNDEF(ws, url) {
    if (!this.currentReader) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
      return;
    }

    // Validate URL first (before any retries)
    if (!url || typeof url !== 'string' || url.trim().length === 0) {
      this.sendError(ws, 'Invalid URL: URL must be a non-empty string');
      return;
    }

    // Ensure URL has protocol
    let urlToWrite = url.trim();
    if (!urlToWrite.startsWith('http://') && !urlToWrite.startsWith('https://')) {
      urlToWrite = 'https://' + urlToWrite;
    }

    // Validate URL length (NDEF has limits)
    if (urlToWrite.length > 200) {
      this.sendError(ws, 'URL too long: Maximum 200 characters supported');
      return;
    }

    const maxRetries = 3;
    let lastError = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Wait for card to be detected and ready (similar to APDU operations)
        await this.waitForCardReady();

        // Verify card is still present and connection is active RIGHT BEFORE operation
        // This is critical: card might have been removed during wait
        if (!this.verifyConnection()) {
          throw new Error('Connection lost, card needs to be re-presented');
        }

        // Create NDEF message with URL record
        const ndefMessage = this.createNDEFUrlRecord(urlToWrite);
        
        if (!ndefMessage || ndefMessage.length === 0) {
          throw new Error('Failed to create NDEF message');
        }

        // Ensure connection is active
        if (!this.currentReader.connection) {
          console.log('Connection not ready, waiting a bit more...');
          await new Promise(resolve => setTimeout(resolve, 200));
          if (!this.currentReader.connection) {
            throw new Error('Connection not established - card may need to be re-presented');
          }
        }

        // For ISO 14443-3 tags, try block write first
        if (this.currentCard.type === TAG_ISO_14443_3) {
          try {
            console.log('Attempting block write for ISO 14443-3 tag...');
            const blockSize = 4;
            const paddedLength = Math.ceil(ndefMessage.length / blockSize) * blockSize;
            const paddedMessage = Buffer.alloc(paddedLength, 0);
            ndefMessage.copy(paddedMessage);
            await this.currentReader.write(4, paddedMessage, blockSize);
            console.log('Block write successful');
          } catch (error) {
            console.log('Block write failed, trying APDU sequence...');
            await this.writeNDEFViaAPDU(ndefMessage);
          }
        } else {
          // For ISO 14443-4 tags, use APDU sequence (block write doesn't work)
          await this.writeNDEFViaAPDU(ndefMessage);
        }
        
        // Write succeeded, verify by reading back
        const verifyUrl = await this.readNDEFInternal();
        if (verifyUrl !== urlToWrite) {
          throw new Error(`Write verification failed: wrote "${urlToWrite}" but read "${verifyUrl}"`);
        }
        
        // Success with verification
        ws.send(JSON.stringify({
          type: 'ndef-written',
          success: true,
          data: { url: urlToWrite, verified: true }
        }));
        return; // Success, exit retry loop
      } catch (error) {
        lastError = error;
        const errorMessage = error.message || String(error);
        const isUnpowered = errorMessage.includes('unpowered') || 
                           (error.previous && error.previous.message && error.previous.message.includes('unpowered'));
        
        // If card is unpowered, clear state and wait for fresh detection
        if (isUnpowered) {
          console.log('Card is unpowered, clearing state and waiting for re-detection...');
          this.currentCard = null;
          this.chipPresent = false;
          
          // Wait for card to be re-detected (will trigger card event)
          if (attempt < maxRetries) {
            console.log(`Waiting for card re-detection (attempt ${attempt}/${maxRetries})...`);
            // Wait a bit for card event to fire
            await new Promise(resolve => setTimeout(resolve, 300));
            // Wait for card to be detected again
            await this.waitForCardReady();
            continue; // Retry with fresh card detection
          }
        }
        
        // Check if this is a retryable error
        const isRetryable = errorMessage.includes('transmitting') || 
                           errorMessage.includes('timeout') ||
                           errorMessage.includes('Card was removed') ||
                           errorMessage.includes('connection') ||
                           isUnpowered;
        
        if (!isRetryable || attempt === maxRetries) {
          // Non-retryable error or max retries reached
          console.error(`NDEF write error (attempt ${attempt}/${maxRetries}):`, error);
          this.sendError(ws, `Failed to write NDEF: ${errorMessage}`);
          return;
        }
        
        // Retryable error - wait a bit and try again
        console.log(`NDEF write attempt ${attempt}/${maxRetries} failed, retrying...`);
        await new Promise(resolve => setTimeout(resolve, 200));
      }
    }
  }

  /**
   * Create NDEF URL record
   * Format: TLV structure for Type 2 tags (NTAG)
   */
  createNDEFUrlRecord(url) {
    // Determine URL prefix
    let prefix = 0x04; // https://
    let urlWithoutPrefix = url;
    
    if (url.startsWith('https://www.')) {
      prefix = 0x02;
      urlWithoutPrefix = url.substring(12);
    } else if (url.startsWith('http://www.')) {
      prefix = 0x01;
      urlWithoutPrefix = url.substring(11);
    } else if (url.startsWith('https://')) {
      prefix = 0x04;
      urlWithoutPrefix = url.substring(8);
    } else if (url.startsWith('http://')) {
      prefix = 0x03;
      urlWithoutPrefix = url.substring(7);
    }
    
    const urlBytes = Buffer.from(urlWithoutPrefix, 'utf-8');
    
    // NDEF Record Header
    // MB=1 (Message Begin), ME=1 (Message End), CF=0, SR=1 (Short Record), IL=0, TNF=0x01 (Well Known Type)
    const recordHeader = 0xD1; // 11010001
    
    // Type Length (1 byte for "U")
    const typeLength = 0x01;
    
    // Payload Length (1 byte for short record: prefix + URL)
    const payloadLength = 1 + urlBytes.length;
    
    // ID Length (0 for no ID)
    const idLength = 0x00;
    
    // Type (U = 0x55)
    const type = 0x55;
    
    // Build NDEF Record
    const ndefRecord = Buffer.concat([
      Buffer.from([recordHeader]),
      Buffer.from([typeLength]),
      Buffer.from([payloadLength]),
      Buffer.from([idLength]),
      Buffer.from([type]),
      Buffer.from([prefix]),
      urlBytes
    ]);
    
    // NDEF Message TLV
    const ndefMessageLength = ndefRecord.length;
    const tlvHeader = Buffer.from([0x03, ndefMessageLength]);
    
    // Terminator TLV
    const terminator = Buffer.from([0xFE]);
    
    // Complete NDEF message
    const ndefMessage = Buffer.concat([tlvHeader, ndefRecord, terminator]);
    
    // Return unpadded message - padding will be handled by write operation
    // to match the block size (4 bytes for Type 2 tags)
    return ndefMessage;
  }

  sendError(ws, message) {
    ws.send(JSON.stringify({
      type: 'error',
      error: message
    }));
  }
}

const server = new NFCServer();
server.start();

console.log('NFC Server ready (using nfc-pcsc for all operations)');
console.log('Place chip on reader 2 to detect');

