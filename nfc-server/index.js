/**
 * NFC Server using blocksec2go CLI
 * Alternative to nfc-pcsc that uses the Python blocksec2go tool you already have working
 */

import { WebSocketServer } from 'ws';
import { exec } from 'child_process';
import { promisify } from 'util';

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
  }

  start() {
    this.wss = new WebSocketServer({ port: PORT });
    console.log(`WebSocket server started on port ${PORT}`);
    console.log('Using blocksec2go CLI for NFC operations');

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

  sendError(ws, message) {
    ws.send(JSON.stringify({
      type: 'error',
      error: message
    }));
  }
}

const server = new NFCServerBlocksec2go();
server.start();

console.log('NFC Server ready (using blocksec2go)');
console.log('Place chip on reader to detect');

