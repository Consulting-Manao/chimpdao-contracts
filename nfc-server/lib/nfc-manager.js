/**
 * NFC Connection Manager
 * Handles NFC reader initialization, card detection, and connection state
 */

import { NFC, TAG_ISO_14443_4 } from "nfc-pcsc";
import { BLOCKCHAIN_AID } from "./constants.js";

export class NFCManager {
  constructor() {
    this.nfc = null;
    this.currentReader = null;
    this.currentCard = null;
    this.chipPresent = false;
    this.cardReadyPromise = null;
    this.cardReadyResolve = null;
  }

  /**
   * Initialize nfc-pcsc for all NFC operations (APDU and NDEF)
   * @param {Function} onStatusChange - Callback for status changes
   */
  init(onStatusChange) {
    this.nfc = new NFC();
    this.onStatusChange = onStatusChange;

    this.nfc.on("reader", (reader) => {
      console.log(`NFC Reader detected: ${reader.reader.name}`);

      // Only Identiv/uTrust dual-interface readers (both (1) and (2) OK)
      const name = reader.reader.name || "";
      if (!name.includes("Identiv") && !name.includes("uTrust")) {
        console.log(`Skipping non-Identiv reader "${name}"`);
        return;
      }

      reader.autoProcessing = false;
      // Set AID before any card event so nfc-pcsc ISO14443-4 path doesn't crash
      reader.aid = BLOCKCHAIN_AID.toString("hex");

      // Track any Identiv interface; card event picks the active one
      if (!this.currentReader) {
        this.currentReader = reader;
        console.log(`Using reader: ${reader.reader.name}`);
      }

      reader.on("card", async (card) => {
        try {
          console.log(
            `Card detected on ${reader.reader.name}: ${card.type}, UID: ${card.uid || "N/A"}`,
          );
          this.currentReader = reader;
          this.currentCard = card;
          this.chipPresent = true;

          await new Promise((resolve) => setTimeout(resolve, 200));

          if (!this.currentCard || !this.chipPresent) {
            console.warn("Card was removed during initialization");
            return;
          }

          if (this.cardReadyResolve) {
            this.cardReadyResolve();
          }
          if (this.onStatusChange) {
            this.onStatusChange();
          }
        } catch (error) {
          console.error("Error handling card detection:", error);
          this.clearCardState();
        }
      });

      reader.on("card.off", (card) => {
        if (this.currentReader !== reader) return;
        console.log("Card removed", card ? `(UID: ${card.uid || "N/A"})` : "");
        this.clearCardState("Card was removed");
      });

      reader.on("error", (err) => {
        // nfc-pcsc still fires this with autoProcessing=false; swallow only.
        if (err.message?.includes("AID was not set")) {
          console.log(
            "NFC: Ignoring AID error (nfc-pcsc library issue with existing cards)",
          );
          return;
        }

        console.error("NFC Reader error:", err);
        if (
          err.message &&
          (err.message.includes("transmitting") ||
            err.message.includes("connection"))
        ) {
          console.warn("Reader connection error detected, clearing card state");
          this.clearCardState();
        }
      });

      // Unplug must not leave a stale Ready in the POS.
      reader.on("end", () => {
        console.log(`NFC Reader ended: ${reader.reader.name}`);
        if (this.currentReader !== reader) return;
        this.clearCardState();
        this.currentReader = null;
      });
    });

    this.nfc.on("error", (err) => {
      console.error("NFC error:", err);
    });
  }

  /**
   * Verify basic prerequisites (reader and card state)
   */
  verifyConnection() {
    return !!(this.currentReader && this.currentCard && this.chipPresent);
  }

  /**
   * Wait for card to be detected and ready for operations
   */
  async waitForCardReady() {
    if (!this.currentReader) {
      throw new Error("No NFC reader available");
    }

    if (this.currentCard && this.chipPresent) {
      if (this.currentCard.type === TAG_ISO_14443_4) {
        if (!this.verifyConnection()) {
          throw new Error("Connection lost, card needs to be re-presented");
        }

        // Try to connect; selectApplication will retry if this fails
        if (!this.currentReader.connection) {
          try {
            this.currentReader.aid = BLOCKCHAIN_AID.toString("hex");
            await this.currentReader.connect();
            console.log("NFC: Connection established");
          } catch {
            try {
              this.currentReader.aid = BLOCKCHAIN_AID;
              await this.currentReader.connect();
              console.log("NFC: Connection established (Buffer AID)");
            } catch (error) {
              console.log(
                "NFC: Connection deferred to BlockchainOps:",
                error.message,
              );
            }
          }
        }

        await new Promise((resolve) => setTimeout(resolve, 100));
        if (!this.verifyConnection()) {
          throw new Error("Connection lost during wait");
        }
        return;
      }

      await new Promise((resolve) => setTimeout(resolve, 50));
      if (!this.currentCard || !this.chipPresent) {
        throw new Error("Card was removed during initialization");
      }
      return;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (
          this.cardReadyPromise &&
          this.cardReadyPromise.resolve === resolve
        ) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        reject(
          new Error(
            "Timeout waiting for card. Please place the chip on the reader.",
          ),
        );
      }, 60_000);

      this.cardReadyPromise = { resolve, reject, timeout };
      this.cardReadyResolve = () => {
        clearTimeout(timeout);
        if (
          this.cardReadyPromise &&
          this.cardReadyPromise.resolve === resolve
        ) {
          this.cardReadyPromise = null;
          this.cardReadyResolve = null;
        }
        resolve();
      };
    });
  }

  /**
   * Clear card state (error recovery, card off, reader end).
   * @param {string} [reason]
   */
  clearCardState(reason = "Card state cleared due to error") {
    this.currentCard = null;
    this.chipPresent = false;
    if (this.cardReadyPromise) {
      const { reject, timeout } = this.cardReadyPromise;
      clearTimeout(timeout);
      this.cardReadyPromise = null;
      this.cardReadyResolve = null;
      reject(new Error(reason));
    }
    // Clients must not keep believing a chip is on the reader after we gave up.
    if (this.onStatusChange) this.onStatusChange();
  }

  getReader() {
    return this.currentReader;
  }

  getCard() {
    return this.currentCard;
  }

  isChipPresent() {
    return this.chipPresent;
  }
}
