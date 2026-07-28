/**
 * Quick chip check: status + pubkey for key 1.
 * Prereq: node index.js (nfc-server) + card on reader.
 */
import { request } from "./ws-client.js";

const status = await request("status");
console.log("status:", status.data);

const pubkey = await request("read-pubkey", { keyId: 1 });
console.log("pubkey:", pubkey.data.publicKey);
console.log("globalCounter:", pubkey.data.globalCounter);
console.log("keyCounter:", pubkey.data.keyCounter);
console.log("ok");
