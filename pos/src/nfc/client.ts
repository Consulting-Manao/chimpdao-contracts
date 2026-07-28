export type NfcStatus = {
  readerConnected: boolean;
  chipPresent: boolean;
  readerName: string | null;
};

type Listener = (status: NfcStatus) => void;

type WsMsg = {
  type: string;
  success?: boolean;
  error?: string;
  data?: {
    publicKey?: string;
    r?: string;
    s?: string;
    readerConnected?: boolean;
    chipPresent?: boolean;
    readerName?: string | null;
  };
};

const DEFAULT_URL = import.meta.env.VITE_NFC_WS || "ws://127.0.0.1:8080";

/** Generous: a customer may be fumbling with the card mid-exchange. */
const REQUEST_TIMEOUT_MS = 60_000;

export class NfcClient {
  private ws: WebSocket | null = null;
  private connecting: Promise<void> | null = null;
  private status: NfcStatus = {
    readerConnected: false,
    chipPresent: false,
    readerName: null,
  };
  private listeners = new Set<Listener>();
  private pending = new Map<
    string,
    { resolve: (v: WsMsg) => void; reject: (e: Error) => void }
  >();

  constructor(private url = DEFAULT_URL) {}

  getStatus(): NfcStatus {
    return { ...this.status };
  }

  onStatus(fn: Listener): () => void {
    this.listeners.add(fn);
    fn(this.getStatus());
    return () => this.listeners.delete(fn);
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  async connect(): Promise<void> {
    if (this.isConnected()) return;
    if (this.connecting) return this.connecting;

    this.connecting = new Promise<void>((resolve, reject) => {
      const offline = () => new Error(`NFC server not running (${this.url})`);
      const ws = new WebSocket(this.url);
      this.ws = ws;
      let opened = false;

      ws.onopen = () => {
        opened = true;
        this.requestStatus();
        resolve();
      };

      ws.onerror = () => {
        if (!opened) reject(offline());
      };

      ws.onclose = () => {
        if (this.ws === ws) this.ws = null;
        this.status = {
          readerConnected: false,
          chipPresent: false,
          readerName: null,
        };
        this.emit();
        for (const [, p] of this.pending) {
          p.reject(new Error("NFC connection closed"));
        }
        this.pending.clear();
        if (!opened) reject(offline());
      };

      ws.onmessage = (ev) => this.onMessage(String(ev.data));
    }).finally(() => {
      this.connecting = null;
    });

    return this.connecting;
  }

  requestStatus(): void {
    if (!this.isConnected()) return;
    this.send({ type: "status" });
  }

  async readPublicKey(): Promise<string> {
    if (!this.status.chipPresent) throw new Error("Place the chip on the reader");
    const msg = await this.request("read-pubkey", "pubkey");
    const pk = msg.data?.publicKey;
    if (!pk) throw new Error("No public key from chip");
    return pk;
  }

  async signDigest(digest: Uint8Array): Promise<Uint8Array> {
    if (digest.length !== 32) throw new Error("digest must be 32 bytes");
    if (!this.status.chipPresent) throw new Error("Place the chip on the reader");
    const messageDigest = Array.from(digest)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    const msg = await this.request("sign", "signature", { messageDigest });
    const { r, s } = msg.data ?? {};
    if (!r || !s || r.length !== 64 || s.length !== 64) {
      throw new Error("Bad signature from chip");
    }
    const out = new Uint8Array(64);
    for (let i = 0; i < 32; i++) {
      out[i] = parseInt(r.slice(i * 2, i * 2 + 2), 16);
      out[32 + i] = parseInt(s.slice(i * 2, i * 2 + 2), 16);
    }
    return out;
  }

  private send(payload: unknown): void {
    if (!this.isConnected()) throw new Error("Not connected to NFC server");
    this.ws!.send(JSON.stringify(payload));
  }

  private request(
    type: string,
    expect: string,
    data?: Record<string, unknown>,
  ): Promise<WsMsg> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(expect);
        reject(new Error(`Timeout waiting for ${expect}`));
      }, REQUEST_TIMEOUT_MS);
      this.pending.set(expect, {
        resolve: (m) => {
          clearTimeout(timer);
          resolve(m);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      try {
        this.send({ type, data });
      } catch (e) {
        clearTimeout(timer);
        this.pending.delete(expect);
        reject(e instanceof Error ? e : new Error(String(e)));
      }
    });
  }

  private onMessage(raw: string): void {
    let msg: WsMsg;
    try {
      msg = JSON.parse(raw) as WsMsg;
    } catch {
      return;
    }

    if (msg.type === "status" && msg.data) {
      this.status = {
        readerConnected: !!msg.data.readerConnected,
        chipPresent: !!msg.data.chipPresent,
        readerName: msg.data.readerName ?? null,
      };
      this.emit();
      const p = this.pending.get("status");
      if (p) {
        this.pending.delete("status");
        p.resolve(msg);
      }
      return;
    }

    if (msg.type === "error") {
      for (const [, p] of this.pending) {
        p.reject(new Error(msg.error || "NFC error"));
      }
      this.pending.clear();
      return;
    }

    const p = this.pending.get(msg.type);
    if (p) {
      this.pending.delete(msg.type);
      if (msg.success === false) {
        p.reject(new Error(msg.error || "NFC request failed"));
      } else {
        p.resolve(msg);
      }
    }
  }

  private emit(): void {
    const s = this.getStatus();
    for (const fn of this.listeners) fn(s);
  }
}

export const nfcClient = new NfcClient();
