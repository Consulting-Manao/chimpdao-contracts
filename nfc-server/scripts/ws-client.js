/**
 * Minimal WebSocket client for nfc-server diagnostics.
 * Usage: node scripts/<script>.js
 * Prereq: `node index.js` running in nfc-server/
 */
import WebSocket from "ws";

const WS_URL = process.env.NFC_WS_URL || "ws://localhost:8080";

export function request(type, data, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error(`timeout waiting for ${type}`));
    }, timeoutMs);

    ws.on("open", () => {
      ws.send(JSON.stringify({ type, data }));
    });

    ws.on("message", (raw) => {
      const msg = JSON.parse(raw.toString());
      // Ignore initial status broadcasts unless we asked for status
      if (msg.type === "status" && type !== "status") return;
      if (msg.type === "error") {
        clearTimeout(timer);
        ws.close();
        reject(new Error(msg.error || "unknown error"));
        return;
      }
      // Match response types to request types
      const ok =
        (type === "status" && msg.type === "status") ||
        (type === "read-pubkey" && msg.type === "pubkey") ||
        (type === "sign" && msg.type === "signature") ||
        (type === "read-ndef" && msg.type === "ndef-read") ||
        (type === "write-ndef" && msg.type === "ndef-written") ||
        (type === "fetch-key" && msg.type === "key-fetched") ||
        (type === "generate-key" && msg.type === "key-generated");
      if (!ok) return;
      clearTimeout(timer);
      ws.close();
      resolve(msg);
    });

    ws.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}
