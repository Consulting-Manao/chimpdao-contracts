/**
 * Read NDEF URL from the chip via nfc-server.
 * Prereq: node index.js (nfc-server) + card on reader.
 */
import { request } from "./ws-client.js";

const status = await request("status");
console.log("status:", status.data);

const ndef = await request("read-ndef");
console.log("ndef:", ndef.data);
console.log("ok");
