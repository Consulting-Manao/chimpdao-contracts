/**
 * NFC Server using blocksec2go CLI for APDU operations
 * and nfc-pcsc for NDEF operations
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
import { exec } from 'child_process';
import { promisify } from 'util';
import { NFC } from 'nfc-pcsc';

const execAsync = promisify(exec);
const PORT = 8080;

// Helper to run blocksec2go commands
async function runBlocksec2go(args, silent = false) {
  const cmd = `uv run --with blocksec2go blocksec2go ${args}`;
  if (!silent) console.log('Running:', cmd);
  
  try {
    const { stdout, stderr } = await execAsync(cmd);
    if (!silent && stdout) console.log('STDOUT:', stdout);
    return { stdout, stderr, success: true };
  } catch (error) {
    // Return error info without logging (caller decides what to log)
    return { stdout: error.stdout || '', stderr: error.stderr || '', success: false, error };
  }
}

class NFCServerBlocksec2go {
  constructor() {
    this.wss = null;
    this.clients = new Set();
    this.chipPresent = false;
    this.nfc = null;
    this.currentReader = null;
    this.initNFC();
  }

  /**
   * Initialize nfc-pcsc for NDEF operations
   */
  initNFC() {
    this.nfc = new NFC();
    
    this.nfc.on('reader', (reader) => {
      console.log(`NFC Reader detected: ${reader.reader.name}`);
      this.currentReader = reader;
      
      reader.on('card', async (card) => {
        console.log(`Card detected: ${card.type}, UID: ${card.uid}`);
        // Update chip presence - but also check with blocksec2go for consistency
        this.chipPresent = true;
        this.broadcastStatus();
      });
      
      reader.on('card.off', () => {
        console.log('Card removed');
        this.chipPresent = false;
        this.broadcastStatus();
      });
      
      reader.on('error', (err) => {
        console.error('NFC Reader error:', err);
      });
    });
    
    this.nfc.on('error', (err) => {
      console.error('NFC error:', err);
    });
  }

  start() {
    this.wss = new WebSocketServer({ port: PORT });
    console.log(`WebSocket server started on port ${PORT}`);
    console.log('Using blocksec2go CLI for APDU operations');
    console.log('Using nfc-pcsc for NDEF operations');

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

  async checkChipStatus() {
    // Run silently - no card is expected and shouldn't spam console
    const result = await runBlocksec2go('get_card_info', true);
    
    const wasPresent = this.chipPresent;
    
    if (result.success) {
      this.chipPresent = true; // If command succeeded, chip is present
      
      if (!wasPresent) {
        this.broadcastStatus();
      }
    } else {
      this.chipPresent = false;
      
      if (wasPresent) {
        this.broadcastStatus();
      }
      // Don't log error when no chip - this is normal
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

    
    const result = await runBlocksec2go(`get_key_info 1`, false); // Show output
    
    if (result.success && result.stdout) {
      // Try to parse public key from output
      // Common formats: "Public key: 04..." or just "04..."
      const match = result.stdout.match(/([0-9a-fA-F]{130}|04[0-9a-fA-F]{128})/);
      if (match) {
        const publicKey = match[1];

        ws.send(JSON.stringify({
          type: 'pubkey',
          success: true,
          data: { publicKey }
        }));
        return;
      }
    }
    
    // If parsing failed, show the actual output for debugging
    console.error('Could not parse public key. Output was:', result.stdout);
    this.sendError(ws, 'Could not parse public key. Check server logs for blocksec2go output.');
  }

  async signMessage(ws, messageDigestHex) {
    if (!this.chipPresent) {
      this.sendError(ws, 'No chip present');
      return;
    }

    // Note: blocksec2go generate_signature expects a 32-byte hash
    // According to Infineon docs, it signs the input directly without additional hashing
    if (!messageDigestHex || messageDigestHex.length !== 64) {
      this.sendError(ws, 'Invalid message digest (must be 32 bytes / 64 hex chars)');
      return;
    }

    
    const result = await runBlocksec2go(`generate_signature 1 ${messageDigestHex}`, false);
    
    if (result.success && result.stdout) {
      // Parse DER-encoded signature from hex
      // Format: "Signature (hex): 3046022100...022100..."
      const sigMatch = result.stdout.match(/Signature\s*\(hex\)\s*:\s*([0-9a-fA-F]+)/i);
      
      if (sigMatch) {
        const derHex = sigMatch[1];
        
        try {
          // Parse DER to extract r and s
          const { r, s } = this.parseDERSignature(derHex);
          
          // blocksec2go doesn't explicitly return v in the output
          // Based on testing, it uses recovery ID 1
          const v = 1;
          const recoveryId = 1;


          ws.send(JSON.stringify({
            type: 'signature',
            success: true,
            data: { r, s, v, recoveryId }
          }));
          return;
        } catch (parseError) {
          console.error('DER parsing failed:', parseError.message);
          this.sendError(ws, `Failed to parse DER signature: ${parseError.message}`);
          return;
        }
      }
    }
    
    console.error('Could not find signature in output:', result.stdout);
    this.sendError(ws, 'Failed to parse signature. Check server logs for blocksec2go output.');
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
    ws.send(JSON.stringify({
      type: 'status',
      data: {
        readerConnected: true, // blocksec2go handles this
        chipPresent: this.chipPresent,
        readerName: 'blocksec2go via uTrust 4701F'
      }
    }));
  }

  broadcastStatus() {
    const status = JSON.stringify({
      type: 'status',
      data: {
        readerConnected: true,
        chipPresent: this.chipPresent,
        readerName: 'blocksec2go via uTrust 4701F'
      }
    });

    this.clients.forEach(client => {
      if (client.readyState === 1) {
        client.send(status);
      }
    });
  }

  /**
   * Read NDEF data from chip
   */
  async readNDEF(ws) {
    if (!this.currentReader) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
      return;
    }

    if (!this.chipPresent) {
      this.sendError(ws, 'No chip present');
      return;
    }

    try {
      // Read NDEF data starting from block 4 (standard Type 2 tag location)
      // Read 16 blocks (256 bytes) which should be enough for most NDEF messages
      const data = await this.currentReader.read(4, 16);
      
      // Parse NDEF message
      const ndefUrl = this.parseNDEFUrl(data);
      
      if (ndefUrl) {
        ws.send(JSON.stringify({
          type: 'ndef-read',
          success: true,
          data: { url: ndefUrl }
        }));
      } else {
        ws.send(JSON.stringify({
          type: 'ndef-read',
          success: true,
          data: { url: null, message: 'No NDEF data found or invalid format' }
        }));
      }
    } catch (error) {
      console.error('NDEF read error:', error);
      this.sendError(ws, `Failed to read NDEF: ${error.message}`);
    }
  }

  /**
   * Parse NDEF URL from raw data
   */
  parseNDEFUrl(data) {
    try {
      // Find NDEF TLV (0x03)
      let offset = 0;
      while (offset < data.length - 2) {
        if (data[offset] === 0x03) {
          const length = data[offset + 1];
          if (length === 0) break; // Empty NDEF message
          
          const ndefStart = offset + 2;
          const ndefEnd = ndefStart + length;
          
          if (ndefEnd > data.length) break;
          
          const ndefData = data.slice(ndefStart, ndefEnd);
          
          // Parse NDEF record
          if (ndefData.length < 5) break;
          
          const recordHeader = ndefData[0];
          const typeLength = ndefData[1];
          const payloadLength = ndefData[2];
          const idLength = ndefData[3];
          
          if (typeLength !== 1) break; // Not a URL record
          
          const typeOffset = 4;
          const type = ndefData[typeOffset];
          
          if (type !== 0x55) break; // Not a URL record (U = 0x55)
          
          const payloadOffset = typeOffset + typeLength + idLength;
          if (payloadOffset + payloadLength > ndefData.length) break;
          
          const payload = ndefData.slice(payloadOffset, payloadOffset + payloadLength);
          
          // Parse URL prefix
          const prefix = payload[0];
          let url = '';
          
          // URL prefix codes: https://www.ndef.org/resources/url-prefixes
          const prefixes = {
            0x00: '',
            0x01: 'http://www.',
            0x02: 'https://www.',
            0x03: 'http://',
            0x04: 'https://',
          };
          
          url = (prefixes[prefix] || '') + payload.slice(1).toString('utf-8');
          
          return url;
        }
        offset++;
      }
      
      return null;
    } catch (error) {
      console.error('NDEF parse error:', error);
      return null;
    }
  }

  /**
   * Write NDEF URL record to chip
   */
  async writeNDEF(ws, url) {
    if (!this.currentReader) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
      return;
    }

    if (!this.chipPresent) {
      this.sendError(ws, 'No chip present');
      return;
    }

    try {
      // Validate URL
      if (!url || typeof url !== 'string') {
        this.sendError(ws, 'Invalid URL');
        return;
      }

      // Ensure URL has protocol
      let urlToWrite = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        urlToWrite = 'https://' + url;
      }

      // Create NDEF message with URL record
      const ndefMessage = this.createNDEFUrlRecord(urlToWrite);

      // Write NDEF message to chip starting at block 4
      await this.currentReader.write(ndefMessage, 4);

      ws.send(JSON.stringify({
        type: 'ndef-written',
        success: true,
        data: { url: urlToWrite }
      }));
    } catch (error) {
      console.error('NDEF write error:', error);
      this.sendError(ws, `Failed to write NDEF: ${error.message}`);
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
    
    // Pad to 16-byte blocks (NTAG requirement)
    const blockSize = 16;
    const paddedLength = Math.ceil(ndefMessage.length / blockSize) * blockSize;
    const padded = Buffer.alloc(paddedLength);
    ndefMessage.copy(padded);
    
    return padded;
  }

  sendError(ws, message) {
    ws.send(JSON.stringify({
      type: 'error',
      error: message
    }));
  }
}

const server = new NFCServerBlocksec2go();
server.start();

console.log('NFC Server ready (using blocksec2go for APDU, nfc-pcsc for NDEF)');
console.log('Place chip on reader to detect');

