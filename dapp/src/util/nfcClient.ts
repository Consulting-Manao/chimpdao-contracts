/**
 * Dapp NFC facade over @chimpdao/nfc-client.
 * Soroban signature formatting stays in crypto.ts.
 */

import { NfcClient, type KeyInfo, type NfcStatus } from "@chimpdao/nfc-client";
import {
  formatSignatureForSoroban,
  type NFCSignature,
  type SorobanSignature,
} from "./crypto.ts";

export type { KeyInfo };
export type NFCStatus = NfcStatus;

export type NFCClientEventType =
  | "status"
  | "error"
  | "connected"
  | "disconnected";

export interface NFCClientEvent {
  type: NFCClientEventType;
  data?: NFCStatus | string;
}

export type NFCClientEventListener = (event: NFCClientEvent) => void;

export class NFCServerNotRunningError extends Error {
  constructor(
    message = "NFC server is not running. Start chimpdao-nfc-bridge: npm start",
  ) {
    super(message);
    this.name = "NFCServerNotRunningError";
  }
}

export class ChipNotPresentError extends Error {
  constructor(
    message = "No NFC chip detected. Please place the chip on the reader.",
  ) {
    super(message);
    this.name = "ChipNotPresentError";
  }
}

export class APDUCommandFailedError extends Error {
  constructor(
    message = "APDU command failed. Reposition the chip and try again.",
  ) {
    super(message);
    this.name = "APDUCommandFailedError";
  }
}

export class RecoveryIdError extends Error {
  constructor(message = "Could not determine recovery ID.") {
    super(message);
    this.name = "RecoveryIdError";
  }
}

const WS_URL =
  (typeof import.meta !== "undefined" &&
    import.meta.env?.VITE_NFC_WS) ||
  "ws://127.0.0.1:8080";

export class NFCClient {
  private inner = new NfcClient(WS_URL);
  private listeners = new Set<NFCClientEventListener>();
  private statusUnsub: (() => void) | null = null;

  async connect(): Promise<void> {
    try {
      if (!this.statusUnsub) {
        this.statusUnsub = this.inner.onStatus((s) => {
          this.emit({ type: "status", data: s });
        });
      }
      await this.inner.connect();
      this.emit({ type: "connected" });
    } catch (e) {
      throw new NFCServerNotRunningError(
        e instanceof Error ? e.message : String(e),
      );
    }
  }

  disconnect(): void {
    this.statusUnsub?.();
    this.statusUnsub = null;
    this.emit({ type: "disconnected" });
  }

  isConnected(): boolean {
    return this.inner.isConnected();
  }

  getStatus(): NFCStatus {
    return this.inner.getStatus();
  }

  requestStatus(): void {
    this.inner.requestStatus();
  }

  async readPublicKey(keyId?: number): Promise<string> {
    await this.ensureChip();
    try {
      return await this.inner.readPublicKey(keyId);
    } catch (e) {
      throw this.mapError(e);
    }
  }

  async signMessage(
    messageDigest: Uint8Array,
    keyId?: number,
  ): Promise<SorobanSignature> {
    await this.ensureChip();
    if (messageDigest.length !== 32) {
      throw new Error("Message digest must be exactly 32 bytes");
    }
    try {
      const rs = await this.inner.signDigest(messageDigest, keyId);
      const r = Array.from(rs.subarray(0, 32))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      const s = Array.from(rs.subarray(32))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
      const nfcSig: NFCSignature = { r, s, v: 0 };
      return formatSignatureForSoroban(nfcSig);
    } catch (e) {
      throw this.mapError(e);
    }
  }

  async readNDEF(): Promise<string | null> {
    await this.ensureChip();
    try {
      return await this.inner.readNDEF();
    } catch (e) {
      throw this.mapError(e);
    }
  }

  async writeNDEF(url: string): Promise<string> {
    await this.ensureChip();
    try {
      return await this.inner.writeNDEF(url);
    } catch (e) {
      throw this.mapError(e);
    }
  }

  async generateKey(): Promise<KeyInfo> {
    await this.ensureChip();
    try {
      return await this.inner.generateKey();
    } catch (e) {
      throw this.mapError(e);
    }
  }

  async fetchKeyById(keyId: number): Promise<KeyInfo> {
    await this.ensureChip();
    try {
      return await this.inner.fetchKeyById(keyId);
    } catch (e) {
      throw this.mapError(e);
    }
  }

  addListener(listener: NFCClientEventListener): void {
    this.listeners.add(listener);
  }

  removeListener(listener: NFCClientEventListener): void {
    this.listeners.delete(listener);
  }

  private async ensureChip(): Promise<void> {
    if (!this.isConnected()) await this.connect();
    if (!this.getStatus().chipPresent) throw new ChipNotPresentError();
  }

  private mapError(err: unknown): Error {
    if (err instanceof Error) {
      const m = err.message;
      if (m.includes("not running") || m.includes("NFC connection")) {
        return new NFCServerNotRunningError(m);
      }
      if (m.includes("Place the chip") || m.includes("chip")) {
        return new ChipNotPresentError(m);
      }
      if (/transmit|SELECT|APDU/i.test(m)) {
        return new APDUCommandFailedError(m);
      }
      if (/recovery/i.test(m)) {
        return new RecoveryIdError(m);
      }
      return err;
    }
    return new Error(String(err));
  }

  private emit(event: NFCClientEvent): void {
    for (const fn of this.listeners) {
      try {
        fn(event);
      } catch {
        /* listener errors are non-fatal */
      }
    }
  }
}

export const nfcClient = new NFCClient();
