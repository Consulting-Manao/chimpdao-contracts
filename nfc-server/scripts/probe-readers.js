/**
 * Probe both Identiv readers; try connect + SELECT + GET KEY on whichever responds.
 */
import { NFC } from "nfc-pcsc";
import { BLOCKCHAIN_AID } from "../lib/constants.js";

const nfc = new NFC();
let done = false;

process.on("uncaughtException", (err) => {
  if (err.message?.includes("AID was not set")) return;
  console.error(err);
});
process.on("unhandledRejection", (reason) => {
  if (reason?.message?.includes("AID was not set")) return;
  console.error(reason);
});

async function tryRead(reader, label) {
  console.log(`[${label}] connect…`);
  reader.aid = BLOCKCHAIN_AID.toString("hex");
  try {
    if (!reader.connection) await reader.connect();
  } catch (e1) {
    reader.aid = BLOCKCHAIN_AID;
    try {
      if (!reader.connection) await reader.connect();
    } catch (e2) {
      console.log(`[${label}] connect fail:`, e2.message);
      return false;
    }
  }
  try {
    const select = Buffer.concat([
      Buffer.from([0x00, 0xa4, 0x04, 0x00, BLOCKCHAIN_AID.length]),
      BLOCKCHAIN_AID,
      Buffer.from([0x00]),
    ]);
    const sel = await reader.transmit(select, 40);
    console.log(`[${label}] SELECT:`, sel.slice(-2).toString("hex"));
    const key = await reader.transmit(
      Buffer.from([0x00, 0x16, 0x01, 0x00, 0x00]),
      255,
    );
    console.log(`[${label}] GET KEY:`, key.slice(-2).toString("hex"));
    console.log(`[${label}] pubkey:`, key.slice(8, 73).toString("hex"));
    return true;
  } catch (e) {
    console.log(`[${label}] APDU fail:`, e.message);
    return false;
  }
}

nfc.on("reader", (reader) => {
  const name = reader.reader.name;
  console.log("reader:", name);
  reader.autoProcessing = false;
  reader.aid = BLOCKCHAIN_AID.toString("hex");

  const go = async (why) => {
    if (done) return;
    console.log(`[${name}] trigger:`, why);
    const ok = await tryRead(reader, name);
    if (ok) {
      done = true;
      console.log("ok");
      process.exit(0);
    }
  };

  reader.on("card", (card) => go(`card ${card.type}`));
  reader.on("error", (err) => go(`error ${err.message}`));

  // Also try immediately in case card is already present
  setTimeout(() => go("poll"), 500);
});

setTimeout(() => {
  console.error("timeout");
  process.exit(1);
}, 12000);
