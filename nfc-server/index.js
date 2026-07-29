/**
 * NFC Server using nfc-pcsc for all APDU and NDEF operations
 *
 * NOTE: This server MUST run with Node.js, not Bun, because @pokusew/pcsclite
 * is a native Node.js module that is incompatible with Bun's runtime.
 */

import { WebSocketServer } from "ws";
import { PORT } from "./lib/constants.js";
import { NFCManager } from "./lib/nfc-manager.js";
import { BlockchainOperations } from "./lib/blockchain-ops.js";
import { NDEFOperations } from "./lib/ndef-ops.js";
import { parseDERSignature } from "./lib/crypto-utils.js";

class NFCServer {
  constructor() {
    this.wss = null;
    this.clients = new Set();
    this.nfcManager = new NFCManager();
    this.blockchainOps = new BlockchainOperations(this.nfcManager);
    this.ndefOps = new NDEFOperations(this.nfcManager);
    // ponytail: one in-flight APDU; status stays free. Ceiling: shared socket across tabs.
    this._apdu = Promise.resolve();

    // Initialize NFC manager; broadcast status on detect/remove
    this.nfcManager.init(() => this.broadcastStatus());
  }

  /** Serialize card ops so transmits never interleave. */
  runApdu(fn) {
    return (this._apdu = this._apdu.then(fn, fn));
  }

  start() {
    this.wss = new WebSocketServer({ port: PORT });
    console.log(`WebSocket server started on port ${PORT}`);
    console.log("Using nfc-pcsc for all NFC operations (APDU and NDEF)");

    this.wss.on("connection", (ws) => {
      console.log("Client connected");
      this.clients.add(ws);

      // Send initial status
      this.checkChipStatus().then(() => this.sendStatus(ws));

      ws.on("message", async (message) => {
        try {
          const request = JSON.parse(message.toString());
          await this.handleRequest(ws, request);
        } catch (error) {
          this.sendError(ws, `Invalid request: ${error.message}`);
        }
      });

      ws.on("close", () => {
        console.log("Client disconnected");
        this.clients.delete(ws);
      });
    });

    console.log("Server ready. Chip status will be checked on-demand.");
  }

  async checkChipStatus() {
    const wasPresent = this.nfcManager.isChipPresent();
    const isPresent =
      this.nfcManager.verifyConnection() &&
      this.nfcManager.getReader()?.connection;

    if (wasPresent !== isPresent) {
      this.broadcastStatus();
    }
  }

  async handleRequest(ws, request) {
    const { type, data } = request;

    switch (type) {
      case "status":
        await this.checkChipStatus();
        this.sendStatus(ws);
        break;

      case "read-pubkey":
        await this.runApdu(() => this.readPublicKey(ws, data?.keyId));
        break;

      case "sign":
        if (!data?.messageDigest || !/^[0-9a-fA-F]{64}$/.test(data.messageDigest)) {
          this.sendError(ws, "Invalid message digest (must be 64 hex chars)");
          break;
        }
        await this.runApdu(() =>
          this.signMessage(ws, data.messageDigest, data?.keyId),
        );
        break;

      case "read-ndef":
        await this.runApdu(() => this.readNDEF(ws));
        break;

      case "write-ndef":
        if (!data?.url) {
          this.sendError(ws, "Missing url in write-ndef request");
          break;
        }
        await this.runApdu(() => this.writeNDEF(ws, data));
        break;

      case "generate-key":
        await this.runApdu(() => this.handleGenerateKey(ws));
        break;

      case "fetch-key":
        if (!data?.keyId) {
          this.sendError(ws, "Missing keyId in fetch-key request");
          break;
        }
        await this.runApdu(() => this.handleFetchKey(ws, data.keyId));
        break;

      default:
        this.sendError(ws, `Unknown request type: ${type}`);
    }
  }

  async handleGenerateKey(ws) {
    try {
      await this.nfcManager.waitForCardReady();

      const keyId = await this.blockchainOps.generateKey();
      const keyInfo = await this.blockchainOps.getKeyInfo(keyId);

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "key-generated",
          success: true,
          data: {
            keyId,
            publicKey: keyInfo.publicKey,
            globalCounter: keyInfo.globalCounter,
            keyCounter: keyInfo.keyCounter,
          },
        }),
      );
    } catch (error) {
      console.error("Error generating key:", error);
      this.sendError(ws, `Failed to generate key: ${error.message}`);
    }
  }

  async handleFetchKey(ws, keyId) {
    try {
      const normalizedKeyId = this._normalizeKeyId(keyId);
      await this.nfcManager.waitForCardReady();

      const keyInfo = await this.blockchainOps.fetchKeyById(normalizedKeyId);

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "key-fetched",
          success: true,
          data: keyInfo,
        }),
      );
    } catch (error) {
      console.error("Error fetching key:", error);
      this.sendError(ws, `Failed to fetch key: ${error.message}`);
    }
  }

  async readPublicKey(ws, keyId = 1) {
    try {
      const normalizedKeyId = this._normalizeKeyId(keyId);
      await this.nfcManager.waitForCardReady();

      const keyInfo = await this.blockchainOps.getKeyInfo(normalizedKeyId);

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "pubkey",
          success: true,
          data: {
            publicKey: keyInfo.publicKey,
            globalCounter: keyInfo.globalCounter,
            keyCounter: keyInfo.keyCounter,
          },
        }),
      );
    } catch (error) {
      console.error("Error reading public key:", error);
      this.sendError(ws, `Failed to read public key: ${error.message}`);
    }
  }

  async signMessage(ws, messageDigestHex, keyId = 1) {
    try {
      if (!messageDigestHex || !/^[0-9a-fA-F]{64}$/.test(messageDigestHex)) {
        throw new Error(
          "Invalid message digest (must be 32 bytes / 64 hex chars)",
        );
      }

      const normalizedKeyId = this._normalizeKeyId(keyId);
      await this.nfcManager.waitForCardReady();

      const messageDigest = Buffer.from(messageDigestHex, "hex");
      const result = await this.blockchainOps.generateSignature(
        normalizedKeyId,
        messageDigest,
      );

      const derHex = result.signature.toString("hex");
      const { r, s } = parseDERSignature(derHex);

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "signature",
          success: true,
          data: { r, s },
        }),
      );
    } catch (error) {
      console.error("Error signing message:", error);
      this.sendError(ws, `Failed to sign message: ${error.message}`);
    }
  }

  async readNDEF(ws) {
    try {
      const ndefUrl = await this.ndefOps.readNDEF();

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "ndef-read",
          success: true,
          data: ndefUrl
            ? { url: ndefUrl }
            : { url: null, message: "No NDEF data found or invalid format" },
        }),
      );
    } catch (error) {
      console.error("NDEF read error:", error);
      this.sendError(ws, `Failed to read NDEF: ${error.message}`);
    }
  }

  async writeNDEF(ws, data) {
    try {
      const urlToWrite = await this.ndefOps.writeNDEF(data.url);

      this.sendIfOpen(
        ws,
        JSON.stringify({
          type: "ndef-written",
          success: true,
          data: { url: urlToWrite, verified: true },
        }),
      );
    } catch (error) {
      console.error("NDEF write error:", error);
      this.sendError(ws, `Failed to write NDEF: ${error.message}`);
    }
  }

  _buildStatusObject() {
    const reader = this.nfcManager.getReader();
    return {
      type: "status",
      data: {
        readerConnected: !!reader,
        chipPresent: this.nfcManager.isChipPresent(),
        readerName: reader ? reader.reader.name : "No reader",
      },
    };
  }

  sendIfOpen(ws, payload) {
    if (ws.readyState === 1) {
      ws.send(payload);
    }
  }

  sendStatus(ws) {
    this.sendIfOpen(ws, JSON.stringify(this._buildStatusObject()));
  }

  broadcastStatus() {
    const status = JSON.stringify(this._buildStatusObject());
    this.clients.forEach((client) => {
      this.sendIfOpen(client, status);
    });
  }

  sendError(ws, message) {
    this.sendIfOpen(
      ws,
      JSON.stringify({
        type: "error",
        error: message,
      }),
    );
  }

  _normalizeKeyId(keyId) {
    if (keyId !== undefined && (keyId < 1 || keyId > 255)) {
      throw new Error("Invalid key ID (must be 1-255)");
    }
    return keyId || 1;
  }

  _isAIDError(error) {
    return error?.message?.includes("AID was not set");
  }
}

const server = new NFCServer();

// Handle the specific nfc-pcsc AID error to prevent server crashes
// This is necessary because nfc-pcsc auto-processes ISO 14443-4 cards even with autoProcessing = false
process.on("uncaughtException", (err) => {
  if (server._isAIDError(err)) {
    console.log(
      "NFC: Ignoring AID error (nfc-pcsc library issue with existing cards)",
    );
    return;
  }
  console.error("Uncaught Exception:", err);
  process.exit(1);
});

process.on("unhandledRejection", (reason) => {
  if (server._isAIDError(reason)) {
    console.log(
      "NFC: Ignoring AID rejection (nfc-pcsc library issue with existing cards)",
    );
    return;
  }
  console.error("Unhandled Rejection:", reason);
});

server.start();

console.log("NFC Server ready. Place chip on the Identiv reader to detect");
