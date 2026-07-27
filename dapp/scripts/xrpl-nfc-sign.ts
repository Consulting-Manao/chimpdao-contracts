/**
 * POC: Infineon NFC chip single-signs an XRPL testnet Payment.
 * Prereq: `bun run nfc-server` + card on reader.
 */
import {
  Client,
  Wallet,
  encode,
  encodeForSigning,
  encodeAccountID,
  xrpToDrops,
} from "xrpl";
import { createHash } from "crypto";
import { nfcClient } from "../src/util/nfcClient.ts";
import { bytesToHex, hexToBytes } from "../src/util/crypto.ts";

// raw 32-byte integer → DER INTEGER (0x02 len bytes)
function derInt(b: Uint8Array): Buffer {
  let v = Buffer.from(b);
  while (v.length > 1 && v[0] === 0) v = v.subarray(1);
  if (v[0]! >= 0x80) v = Buffer.concat([Buffer.from([0]), v]);
  return Buffer.concat([Buffer.from([0x02, v.length]), v]);
}

const client = new Client("wss://s.altnet.rippletest.net:51233");
await client.connect();
await nfcClient.connect();

try {
  // wait for card
  const deadline = Date.now() + 15_000;
  while (!nfcClient.getStatus().chipPresent) {
    if (Date.now() > deadline) throw new Error("chip not on reader");
    nfcClient.requestStatus();
    await Bun.sleep(500);
  }

  // 65-byte SEC1 → 33-byte compressed → XRPL address
  const raw = hexToBytes(await nfcClient.readPublicKey());
  if (raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad pubkey");
  const compressed = new Uint8Array([
    raw[64]! % 2 === 0 ? 0x02 : 0x03,
    ...raw.slice(1, 33),
  ]);
  const signingPubKey = bytesToHex(compressed).toUpperCase();
  const chipAddress = encodeAccountID(
    createHash("ripemd160")
      .update(createHash("sha256").update(compressed).digest())
      .digest(),
  );
  console.log("chip:", chipAddress, signingPubKey);

  // fund chip account via faucet throwaway
  const funder = Wallet.generate("ecdsa-secp256k1");
  await client.fundWallet(funder);
  const fund = await client.submitAndWait(
    funder.sign(
      await client.autofill({
        TransactionType: "Payment",
        Account: funder.address,
        Destination: chipAddress,
        Amount: xrpToDrops("12"),
      }),
    ).tx_blob,
  );
  console.log("funded:", fund.result.meta?.TransactionResult);

  // chip-signed payment back to funder
  const prepared = await client.autofill({
    TransactionType: "Payment",
    Account: chipAddress,
    Destination: funder.address,
    Amount: xrpToDrops("1"),
  });
  const unsigned = { ...prepared, SigningPubKey: signingPubKey };

  // encodeForSigning already includes STX\0; SHA-512Half
  const hash = new Uint8Array(
    createHash("sha512")
      .update(Buffer.from(encodeForSigning(unsigned), "hex"))
      .digest()
      .subarray(0, 32),
  );
  console.log("hash:", bytesToHex(hash));

  const { signatureBytes } = await nfcClient.signMessage(hash);
  const r = derInt(signatureBytes.subarray(0, 32));
  const s = derInt(signatureBytes.subarray(32));
  const txnSignature = Buffer.concat([
    Buffer.from([0x30, r.length + s.length]),
    r,
    s,
  ])
    .toString("hex")
    .toUpperCase();

  const result = await client.submitAndWait(
    encode({ ...unsigned, TxnSignature: txnSignature }),
  );
  console.log("result:", result.result.meta?.TransactionResult);
  console.log("hash:", result.result.hash);
  console.log(
    "explorer:",
    `https://testnet.xrpl.org/transactions/${result.result.hash}`,
  );
} finally {
  await client.disconnect();
  nfcClient.disconnect();
}
