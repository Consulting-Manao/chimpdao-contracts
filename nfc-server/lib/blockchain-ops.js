/**
 * Blockchain Application APDU Operations
 * Handles all operations related to the Blockchain Security 2Go application
 */

import { BLOCKCHAIN_AID } from "./constants.js";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * A card that just landed on the reader usually fails its first SELECT with
 * SCARD 0x80100016 ("transaction failed") because `card.on` fires before the RF
 * link is usable. Reconnect and retry instead of failing the whole payment.
 */
const SELECT_ATTEMPTS = 4;

export class BlockchainOperations {
  constructor(nfcManager) {
    this.nfcManager = nfcManager;
  }

  /**
   * Select Blockchain application.
   * Always SELECT; avoids wrong-app state after NDEF operations.
   */
  async selectApplication() {
    for (let attempt = 1; attempt <= SELECT_ATTEMPTS; attempt++) {
      try {
        return await this._selectOnce();
      } catch (error) {
        // Give up early if the card really left: retrying an empty field is noise.
        if (attempt === SELECT_ATTEMPTS || !this.nfcManager.isChipPresent()) {
          this.nfcManager.clearCardState();
          throw error;
        }
        console.warn(
          `selectApplication: attempt ${attempt}/${SELECT_ATTEMPTS} failed (${error.message}), reconnecting`,
        );
        await this._dropConnection();
        await sleep(80 * attempt);
      }
    }
  }

  /** Force the next attempt through reader.connect() with a fresh handle. */
  async _dropConnection() {
    const reader = this.nfcManager.getReader();
    if (!reader?.connection) return;
    try {
      await reader.disconnect();
    } catch {
      reader.connection = null; // card already gone; the handle is dead either way
    }
  }

  async _selectOnce() {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection()) {
      throw new Error("Connection not available");
    }

    if (!reader.connection) {
      console.log("BlockchainOps: Establishing connection...");
      try {
        reader.aid = BLOCKCHAIN_AID.toString("hex");
        await reader.connect();
        console.log("BlockchainOps: Connection established");
      } catch {
        try {
          reader.aid = BLOCKCHAIN_AID;
          await reader.connect();
          console.log("BlockchainOps: Connection established (Buffer AID)");
        } catch (retryError) {
          throw new Error(
            `Failed to establish connection to card: ${retryError.message}`,
          );
        }
      }
    }

    await sleep(100);

    if (
      !reader.connection ||
      !this.nfcManager.getCard() ||
      !this.nfcManager.isChipPresent()
    ) {
      throw new Error("Connection lost during initialization");
    }

    const selectApp = Buffer.concat([
      Buffer.from([0x00, 0xa4, 0x04, 0x00, BLOCKCHAIN_AID.length]),
      BLOCKCHAIN_AID,
      Buffer.from([0x00]),
    ]);

    let response;
    try {
      response = await reader.transmit(selectApp, 40);
    } catch (error) {
      throw new Error(`Failed to transmit SELECT command: ${error.message}`);
    }

    if (response.length < 2) {
      throw new Error(`Invalid response length: ${response.length}`);
    }

    const status = response.slice(-2);
    if (status[0] !== 0x90 || status[1] !== 0x00) {
      const statusHex = status.toString("hex");
      console.error(`selectApplication: Failed with status: ${statusHex}`);
      throw new Error(
        `Failed to select Blockchain application: status=${statusHex}`,
      );
    }

    return true;
  }

  /**
   * Get key information including public key and signature counters
   */
  async getKeyInfo(keyHandle = 1) {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection()) {
      throw new Error("Connection not available");
    }

    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }

    try {
      await this.selectApplication();
      await new Promise((resolve) => setTimeout(resolve, 50));

      if (
        !reader.connection ||
        !this.nfcManager.getCard() ||
        !this.nfcManager.isChipPresent()
      ) {
        throw new Error("Connection lost after SELECT application");
      }

      const getKeyInfo = Buffer.from([0x00, 0x16, keyHandle, 0x00, 0x00]);

      const response = await reader.transmit(getKeyInfo, 255);

      if (
        response.length < 2 ||
        response[response.length - 2] !== 0x90 ||
        response[response.length - 1] !== 0x00
      ) {
        const statusHex = response.slice(-2).toString("hex");
        const statusCode =
          (response[response.length - 2] << 8) | response[response.length - 1];

        if (statusCode === 0x6a88) {
          throw new Error(`Key ID ${keyHandle} does not exist on this chip`);
        }

        console.error(`getKeyInfo: Failed with status: ${statusHex}`);
        throw new Error(`Failed to get key info: status=${statusHex}`);
      }

      const data = response.slice(0, response.length - 2);

      if (data.length < 73) {
        throw new Error(
          `Invalid key info response: expected at least 73 bytes (4+4+65), got ${data.length}`,
        );
      }

      const globalCounter = data.readUInt32BE(0);
      const keyCounter = data.readUInt32BE(4);
      const publicKey = data.slice(8, 73);

      if (publicKey.length !== 65) {
        throw new Error(
          `Invalid public key length: expected 65 bytes, got ${publicKey.length}`,
        );
      }

      const publicKeyHex = publicKey.toString("hex");

      return {
        publicKey: publicKeyHex,
        globalCounter,
        keyCounter,
      };
    } catch (error) {
      console.error("getKeyInfo: Error:", error);
      if (
        error.message &&
        (error.message.includes("unpowered") ||
          error.message.includes("Connection") ||
          error.message.includes("transmit"))
      ) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }

  /**
   * Generate a new keypair on the chip
   */
  async generateKey() {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection()) {
      throw new Error("Connection not available");
    }

    try {
      await this.selectApplication();
      await new Promise((resolve) => setTimeout(resolve, 50));

      if (
        !reader.connection ||
        !this.nfcManager.getCard() ||
        !this.nfcManager.isChipPresent()
      ) {
        throw new Error("Connection lost after SELECT application");
      }

      const generateKey = Buffer.from([0x00, 0x02, 0x00, 0x00, 0x00]);

      const response = await reader.transmit(generateKey, 40);

      if (
        response.length < 2 ||
        response[response.length - 2] !== 0x90 ||
        response[response.length - 1] !== 0x00
      ) {
        const statusHex = response.slice(-2).toString("hex");
        console.error(`generateKey: Failed with status: ${statusHex}`);
        throw new Error(`Failed to generate key: status=${statusHex}`);
      }

      const keyId = response[0];

      return keyId;
    } catch (error) {
      console.error("generateKey: Error:", error);
      if (
        error.message &&
        (error.message.includes("unpowered") ||
          error.message.includes("Connection") ||
          error.message.includes("transmit"))
      ) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }

  /**
   * Fetch key information by key ID
   */
  async fetchKeyById(keyId) {
    if (!keyId || keyId < 1 || keyId > 255) {
      throw new Error(`Invalid key ID: ${keyId} (must be 1-255)`);
    }

    const keyInfo = await this.getKeyInfo(keyId);
    return {
      keyId,
      publicKey: keyInfo.publicKey,
      globalCounter: keyInfo.globalCounter,
      keyCounter: keyInfo.keyCounter,
    };
  }

  /**
   * Generate signature for a 32-byte message hash
   */
  async generateSignature(keyHandle, messageDigest) {
    const reader = this.nfcManager.getReader();
    if (!this.nfcManager.verifyConnection()) {
      throw new Error("Connection not available");
    }

    if (!messageDigest || messageDigest.length !== 32) {
      throw new Error("Message digest must be exactly 32 bytes");
    }

    if (keyHandle < 0 || keyHandle > 255) {
      throw new Error(`Invalid keyHandle: ${keyHandle} (must be 0-255)`);
    }

    try {
      await this.selectApplication();
      await new Promise((resolve) => setTimeout(resolve, 50));

      if (
        !reader.connection ||
        !this.nfcManager.getCard() ||
        !this.nfcManager.isChipPresent()
      ) {
        throw new Error("Connection lost after SELECT application");
      }

      const generateSig = Buffer.concat([
        Buffer.from([0x00, 0x18, keyHandle, 0x00, 0x20]),
        messageDigest,
        Buffer.from([0x00]),
      ]);

      const response = await reader.transmit(generateSig, 255);

      if (
        response.length < 2 ||
        response[response.length - 2] !== 0x90 ||
        response[response.length - 1] !== 0x00
      ) {
        const statusHex = response.slice(-2).toString("hex");
        console.error(`generateSignature: Failed with status: ${statusHex}`);
        throw new Error(`Failed to generate signature: status=${statusHex}`);
      }

      const data = response.slice(0, response.length - 2);

      if (data.length < 8) {
        throw new Error(
          `Invalid signature response: expected at least 8 bytes (counters), got ${data.length}`,
        );
      }

      const globalCounter = data.readUInt32BE(0);
      const keyCounter = data.readUInt32BE(4);
      const derSignature = data.slice(8);

      return {
        signature: derSignature,
        globalCounter,
        keyCounter,
      };
    } catch (error) {
      console.error("generateSignature: Error:", error);
      if (
        error.message &&
        (error.message.includes("unpowered") ||
          error.message.includes("Connection") ||
          error.message.includes("transmit"))
      ) {
        this.nfcManager.clearCardState();
      }
      throw error;
    }
  }
}
