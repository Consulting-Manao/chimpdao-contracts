/**
 * Diagnose NFC bridge: status → pubkey → sign a fixed 32-byte digest.
 * Prereq: node index.js (nfc-server) + card on reader.
 */
import { createHash } from "crypto";
import { request } from "./ws-client.js";

const status = await request("status");
console.log("status:", status.data);
if (!status.data?.chipPresent) {
  throw new Error("chip not present — place card on reader (2)");
}

const pubkey = await request("read-pubkey", { keyId: 1 });
console.log("pubkey:", pubkey.data.publicKey);

const digest = createHash("sha256").update("nfc-diagnose").digest("hex");
console.log("digest:", digest);

const sig = await request("sign", { messageDigest: digest, keyId: 1 });
console.log("r:", sig.data.r);
console.log("s:", sig.data.s);
if (!sig.data?.r || !sig.data?.s || sig.data.r.length !== 64 || sig.data.s.length !== 64) {
  throw new Error("bad signature payload");
}
console.log("ok");
