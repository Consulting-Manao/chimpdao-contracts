/**
 * Direct reader check (no WebSocket). Sets AID early, same as nfc-server.
 * Prereq: stop nfc-server first (exclusive PC/SC lock). Card on reader (2).
 */
import { NFC } from "nfc-pcsc";
import { BLOCKCHAIN_AID } from "../lib/constants.js";

const nfc = new NFC();
let done = false;
let activeReader = null;

async function tryRead(reader) {
  if (done) return;
  if (!reader.connection) {
    reader.aid = BLOCKCHAIN_AID.toString("hex");
    try {
      await reader.connect();
    } catch {
      reader.aid = BLOCKCHAIN_AID;
      await reader.connect();
    }
  }
  const select = Buffer.concat([
    Buffer.from([0x00, 0xa4, 0x04, 0x00, BLOCKCHAIN_AID.length]),
    BLOCKCHAIN_AID,
    Buffer.from([0x00]),
  ]);
  const sel = await reader.transmit(select, 40);
  console.log("SELECT:", sel.slice(-2).toString("hex"));
  const key = await reader.transmit(
    Buffer.from([0x00, 0x16, 0x01, 0x00, 0x00]),
    255,
  );
  console.log("GET KEY:", key.slice(-2).toString("hex"));
  console.log("pubkey:", key.slice(8, 73).toString("hex"));
  done = true;
  console.log("ok");
  process.exit(0);
}

process.on("uncaughtException", async (err) => {
  if (!err.message?.includes("AID was not set")) throw err;
  console.log("AID throw — manual read");
  if (activeReader) {
    try {
      await tryRead(activeReader);
    } catch (e) {
      console.error("manual fail:", e.message);
      process.exit(1);
    }
  }
});
process.on("unhandledRejection", async (reason) => {
  if (!reason?.message?.includes("AID was not set")) throw reason;
  console.log("AID rejection — manual read");
  if (activeReader) {
    try {
      await tryRead(activeReader);
    } catch (e) {
      console.error("manual fail:", e.message);
      process.exit(1);
    }
  }
});

nfc.on("reader", (reader) => {
  console.log("reader:", reader.reader.name);
  if (!reader.reader.name.includes("(2)")) return;

  activeReader = reader;
  reader.autoProcessing = false;
  reader.aid = BLOCKCHAIN_AID.toString("hex");

  reader.on("card", async (card) => {
    console.log("card:", card.type);
    try {
      await tryRead(reader);
    } catch (err) {
      console.error("fail:", err.message);
      process.exit(1);
    }
  });

  reader.on("error", async (err) => {
    if (!err.message?.includes("AID was not set")) {
      console.error("reader error:", err.message);
      return;
    }
    console.log("AID error event — manual read");
    try {
      await tryRead(reader);
    } catch (e) {
      console.error("manual fail:", e.message);
      process.exit(1);
    }
  });
});

setTimeout(() => {
  console.error("timeout — re-place card on reader (2)");
  process.exit(1);
}, 15000);
