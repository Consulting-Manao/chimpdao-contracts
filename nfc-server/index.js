/**
 * NFC Server using nfc-pcsc for all APDU and NDEF operations
 * 
 * NOTE: This server MUST run with Node.js, not Bun, because @pokusew/pcsclite
 * is a native Node.js module that is incompatible with Bun's runtime.
 */

import { WebSocketServer } from 'ws';
import { PORT } from './lib/constants.js';
import { NFCManager } from './lib/nfc-manager.js';
import { BlockchainOperations } from './lib/blockchain-ops.js';
import { NDEFOperations } from './lib/ndef-ops.js';
import { parseDERSignature } from './lib/crypto-utils.js';

class NFCServer {
  constructor() {
    this.wss = null;
    this.clients = new Set();
    this.nfcManager = new NFCManager();
    this.blockchainOps = new BlockchainOperations(this.nfcManager);
    this.ndefOps = new NDEFOperations(this.nfcManager);
    
    // Initialize NFC manager with callbacks
    this.nfcManager.init(
      () => {}, // onCardDetected
      () => {}, // onCardRemoved
      () => this.broadcastStatus() // onStatusChange
    );
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

    console.log('Server ready. Chip status will be checked on-demand.');
  }

  async checkChipStatus() {
    const wasPresent = this.nfcManager.isChipPresent();
    
    if (this.nfcManager.verifyConnection() && this.nfcManager.getReader()?.connection) {
      if (!wasPresent) {
        this.broadcastStatus();
      }
    } else {
      if (wasPresent) {
        this.broadcastStatus();
      }
    }
  }

  async handleRequest(ws, request) {
    const { type, data } = request;

    switch (type) {
      case 'status':
        await this.checkChipStatus();
        this.sendStatus(ws);
        break;

      case 'read-pubkey':
        await this.readPublicKey(ws, data?.keyId);
        break;

      case 'sign':
        await this.signMessage(ws, data.messageDigest, data?.keyId);
        break;

      case 'read-ndef':
        await this.readNDEF(ws);
        break;

      case 'write-ndef':
        await this.writeNDEF(ws, data);
        break;

      case 'generate-key':
        await this.handleGenerateKey(ws);
        break;

      case 'fetch-key':
        await this.handleFetchKey(ws, data.keyId);
        break;

      default:
        this.sendError(ws, `Unknown request type: ${type}`);
    }
  }

  async handleGenerateKey(ws) {
    if (!this.nfcManager.isChipPresent()) {
      this.sendError(ws, 'No chip present');
      return;
    }

    try {
      await this.nfcManager.waitForCardReady();
      
      const keyId = await this.blockchainOps.generateKey();
      const keyInfo = await this.blockchainOps.getKeyInfo(keyId);
      
      ws.send(JSON.stringify({
        type: 'key-generated',
        success: true,
        data: {
          keyId,
          publicKey: keyInfo.publicKey,
          globalCounter: keyInfo.globalCounter,
          keyCounter: keyInfo.keyCounter
        }
      }));
    } catch (error) {
      console.error('Error generating key:', error);
      this.sendError(ws, `Failed to generate key: ${error.message}`);
    }
  }

  async handleFetchKey(ws, keyId) {
    if (!this.nfcManager.isChipPresent()) {
      this.sendError(ws, 'No chip present');
      return;
    }

    if (!keyId || keyId < 1 || keyId > 255) {
      this.sendError(ws, 'Invalid key ID (must be 1-255)');
      return;
    }

    try {
      await this.nfcManager.waitForCardReady();
      
      const keyInfo = await this.blockchainOps.fetchKeyById(keyId);
      
      ws.send(JSON.stringify({
        type: 'key-fetched',
        success: true,
        data: keyInfo
      }));
    } catch (error) {
      console.error('Error fetching key:', error);
      if (error.message && error.message.includes('does not exist')) {
        ws.send(JSON.stringify({
          type: 'key-fetched',
          success: false,
          data: { keyId, error: 'Key not found' },
          message: `Key ID ${keyId} does not exist on this chip. Generate a key first or try a different key ID.`
        }));
      } else {
        this.sendError(ws, `Failed to fetch key: ${error.message}`);
      }
    }
  }

  async readPublicKey(ws, keyId = 1) {
    if (!this.nfcManager.isChipPresent()) {
      this.sendError(ws, 'No chip present');
      return;
    }

    // Validate keyId if provided
    if (keyId !== undefined && (keyId < 1 || keyId > 255)) {
      this.sendError(ws, 'Invalid key ID (must be 1-255)');
      return;
    }

    try {
      await this.nfcManager.waitForCardReady();
      
      const keyIdToUse = keyId || 1;
      const keyInfo = await this.blockchainOps.getKeyInfo(keyIdToUse);

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

  async signMessage(ws, messageDigestHex, keyId = 1) {
    if (!this.nfcManager.isChipPresent()) {
      this.sendError(ws, 'No chip present');
      return;
    }

      if (!messageDigestHex || messageDigestHex.length !== 64) {
        this.sendError(ws, 'Invalid message digest (must be 32 bytes / 64 hex chars)');
        return;
      }

      // Validate keyId if provided
      if (keyId !== undefined && (keyId < 1 || keyId > 255)) {
        this.sendError(ws, 'Invalid key ID (must be 1-255)');
        return;
      }

      try {
        await this.nfcManager.waitForCardReady();
        
        const messageDigest = Buffer.from(messageDigestHex, 'hex');
        
        if (messageDigest.length !== 32) {
          this.sendError(ws, 'Invalid message digest length');
          return;
        }
        
        const keyIdToUse = keyId || 1;
        const result = await this.blockchainOps.generateSignature(keyIdToUse, messageDigest);
        
        // Parse DER-encoded signature to extract r and s
        const derHex = result.signature.toString('hex');
        const { r, s, wasNormalized } = parseDERSignature(derHex);
        
        // Adjust recovery_id when s is normalized
        // When s is normalized (s -> n-s), recovery_id must be adjusted: recovery_id XOR 1
        // Original recovery_id from blockchain2go is 1, so:
        // - If s was normalized: recovery_id = 0 (1 XOR 1)
        // - If s was not normalized: recovery_id = 1 (1 XOR 0)
        const recoveryId = wasNormalized ? 0 : 1;

          ws.send(JSON.stringify({
            type: 'signature',
            success: true,
            data: { r, s, recoveryId }
          }));
    } catch (error) {
      console.error('Error signing message:', error);
      this.sendError(ws, `Failed to sign message: ${error.message}`);
    }
  }

  async readNDEF(ws) {
    if (!this.nfcManager.getReader()) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
          return;
        }

    try {
      const ndefUrl = await this.ndefOps.readNDEF();
      
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

  async writeNDEF(ws, data) {
    if (!this.nfcManager.getReader()) {
      this.sendError(ws, 'No NFC reader available. Make sure reader is connected.');
      return;
    }

    const { url } = data;

    try {
      const urlToWrite = await this.ndefOps.writeNDEF(url);
      
      ws.send(JSON.stringify({
        type: 'ndef-written',
        success: true,
        data: { url: urlToWrite, verified: true }
      }));
    } catch (error) {
      console.error('NDEF write error:', error);
      this.sendError(ws, `Failed to write NDEF: ${error.message}`);
    }
  }

  sendStatus(ws) {
    const reader = this.nfcManager.getReader();
    const readerName = reader ? reader.reader.name : 'No reader';
    ws.send(JSON.stringify({
      type: 'status',
      data: {
        readerConnected: !!reader,
        chipPresent: this.nfcManager.isChipPresent(),
        readerName
      }
    }));
  }

  broadcastStatus() {
    const reader = this.nfcManager.getReader();
    const readerName = reader ? reader.reader.name : 'No reader';
    const status = JSON.stringify({
      type: 'status',
      data: {
        readerConnected: !!reader,
        chipPresent: this.nfcManager.isChipPresent(),
        readerName
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

const server = new NFCServer();
server.start();

console.log('NFC Server ready (using nfc-pcsc for all operations)');
console.log('Place chip on reader 2 to detect');
