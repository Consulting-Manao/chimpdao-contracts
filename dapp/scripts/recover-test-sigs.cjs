/**
 * NFC test signature recovery — single script for regenerating test sigs.
 *
 * Full one-shot instructions: see dapp/scripts/REGENERATE_NFC_TEST_SIGS.md
 *
 * Short flow:
 * 1. Get hashes: cargo test -p nfc-nft test_print_message_hash_for_signing -- --nocapture
 * 2. Sign hash 1–3 with Chip 1, hash 4–5 with Chip 2 (DER hex).
 * 3. Paste the 5 DER hex strings into DER_SIGS below.
 * 4. From repo root: node dapp/scripts/recover-test-sigs.cjs
 * 5. Paste output into contracts/nfc-nft/src/test.rs:
 *    - Replace entire const CHIP1_PUBLIC_KEY: [u8; 65] = [ ... ];
 *    - Replace entire const CHIP2_PUBLIC_KEY: [u8; 65] = [ ... ];
 *    - In each of the 5 TestSignature { } entries, replace only sig_r: [ ... ], and sig_s: [ ... ], (8 lines per entry) with the corresponding Signature 1..5 block from this output.
 */
const path = require("path");
const { execSync } = require("child_process");
const { recoverPublicKey, Point } = require("@noble/secp256k1");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

function getHashesFromTest() {
  try {
    const out = execSync(
      "cargo test -p nfc-nft test_print_message_hash_for_signing -- --nocapture 2>&1",
      { cwd: REPO_ROOT, encoding: "utf-8", maxBuffer: 1024 * 1024 },
    );
    const lines = out.split("\n");
    const hashes = [];
    for (const line of lines) {
      const m = line.match(/Message hash \(hex\):\s*([0-9a-fA-F]{64})/);
      if (m) hashes.push(m[1].toLowerCase());
    }
    if (hashes.length === 5) return hashes;
  } catch (_) {}
  return null;
}

const FALLBACK_HASHES = [
  "c112da331f232ecdb20387cb428d7cfc81ad2f85862ab330b7df7daac2c71bdf",
  "324eb76a50db1335a5c0a662fb35c8d8d1af0554b28d885e802c15a7f5d77f97",
  "5f2f3261a1958aab8e82af3e07c6e4b52e480ec6c3f7a10d86f31e63525a7abf",
  "500b944b11490efab9f946e50b8f44fd422d79a61f3f364a035072ff37fe0c2b",
  "d417f7bd69632961b3c59d08a45d2cb4b07e17f4037333d7cc711fceaa5788af",
];
const hashesFromTest = getHashesFromTest();
const HASHES_HEX = hashesFromTest || FALLBACK_HASHES;
if (!hashesFromTest) {
  console.error(
    "Warning: could not get hashes from test; using fallback. Run from repo root: node dapp/scripts/recover-test-sigs.cjs\n",
  );
}

const DER_SIGS = [
  "3045022100f9ec5f1293c21ec53235fde29ca592efc21b18dc1955f4bf0daa27a1aa24a5e202206aa071095efd37d65e7e186aebc3d7b8287de26e757d138d5eed8610e48a2891",
  "3045022100eba4ab7b96e3eaa721d4806369dcd6b98976bcfe71bae4081f3e87b9c0a48913022043c1a33c9073b9ca6a870e04a827710cff99f5127f873a999803320023bf7717",
  "304402207a0183828df876f5dbf25004166b928456b22794118b4c7c5b248fe23a2f4bbd0220198ad9c41775e1506c8ab87903495fcc62626abe71a67ffa7f3a14032172f747",
  "30450221009069719e2d2c63b33e477b0b3d2b6e3a06c75182d04e2269406b25b0afe28cbf022050cb8884c366273ce5e85e3187a4e8b5a0f686f6b1bfbd21a41d998921957b31",
  "3045022100fafc7a18dded25e3c43c0149bc7a2a26f03feb4d9165ac1c4e47739156e8ec7d022022c7fe08bd7451069a3235b9d0377a2b380f579b7c41b4ea09d08f66ce60c45a",
];

function hexToBytes(hex) {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  const padded = clean.length % 2 === 0 ? clean : "0" + clean;
  return Buffer.from(padded, "hex");
}

function parseDer(derHex) {
  const der = hexToBytes(derHex);
  let pos = 0;
  if (der[pos++] !== 0x30) throw new Error("Invalid DER: expected 0x30");
  let seqLen = der[pos++];
  if (seqLen === 0x81) seqLen = der[pos++];
  else if (seqLen === 0x82) {
    seqLen = (der[pos] << 8) | der[pos + 1];
    pos += 2;
  }
  if (der[pos++] !== 0x02) throw new Error("Invalid DER: expected 0x02 for R");
  const rLen = der[pos++];
  let rBytes = der.slice(pos, pos + rLen);
  pos += rLen;
  if (rBytes.length > 32 && rBytes[0] === 0x00) rBytes = rBytes.slice(1);
  const sigR = Buffer.alloc(32);
  if (rBytes.length <= 32) rBytes.copy(sigR, 32 - rBytes.length);
  else rBytes.slice(rBytes.length - 32).copy(sigR);
  if (der[pos++] !== 0x02) throw new Error("Invalid DER: expected 0x02 for S");
  const sLen = der[pos++];
  let sBytes = der.slice(pos, pos + sLen);
  if (sBytes.length > 32 && sBytes[0] === 0x00) sBytes = sBytes.slice(1);
  const sigS = Buffer.alloc(32);
  if (sBytes.length <= 32) sBytes.copy(sigS, 32 - sBytes.length);
  else sBytes.slice(sBytes.length - 32).copy(sigS);
  return { sigR, sigS };
}

const CURVE_ORDER = Buffer.from([
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
  0xff, 0xff, 0xfe, 0xba, 0xae, 0xdc, 0xe6, 0xaf, 0x48, 0xa0, 0x3b, 0xbf, 0xd2,
  0x5e, 0x8c, 0xd0, 0x36, 0x41, 0x41,
]);
const HALF_ORDER = Buffer.from([
  0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
  0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x5d, 0x57,
  0x6e, 0x73, 0x57, 0xa4, 0x50, 0x1d,
]);

function normalizeS(s) {
  let gt = false;
  for (let i = 0; i < 32; i++) {
    if (s[i] > HALF_ORDER[i]) {
      gt = true;
      break;
    }
    if (s[i] < HALF_ORDER[i]) break;
  }
  if (!gt) return Buffer.from(s);
  const out = Buffer.alloc(32);
  let borrow = 0;
  for (let i = 31; i >= 0; i--) {
    let diff = CURVE_ORDER[i] - s[i] - borrow;
    if (diff < 0) {
      diff += 256;
      borrow = 1;
    } else borrow = 0;
    out[i] = diff;
  }
  return out;
}

/** Recover public key with a specific recovery ID (0-3). Uses normalized S. Throws if recovery fails. */
function recoverPubKeyWithRid(messageHashBytes, sigR, sigS, recoveryId) {
  const sig = Buffer.alloc(65);
  sig[0] = recoveryId;
  sigR.copy(sig, 1);
  sigS.copy(sig, 33);
  const compressed = recoverPublicKey(sig, messageHashBytes, {
    prehash: false,
  });
  const point = Point.fromBytes(compressed);
  return Buffer.from(point.toBytes(false));
}

/** Try recovery IDs 0-3 and return first successful public key. Uses normalized S. */
function recoverPubKey(messageHashBytes, sigR, sigS) {
  for (let rid = 0; rid <= 3; rid++) {
    try {
      return recoverPubKeyWithRid(messageHashBytes, sigR, sigS, rid);
    } catch (_) {}
  }
  throw new Error("No recovery ID matched");
}

function fmtRustBytes(arr) {
  const lines = [];
  for (let row = 0; row < 2; row++) {
    const chunk = Array.from(arr.slice(row * 16, row * 16 + 16))
      .map((b) => "0x" + b.toString(16).padStart(2, "0"))
      .join(", ");
    lines.push("            " + chunk + ",");
  }
  return lines.join("\n");
}

function fmt65Rust(arr) {
  const parts = [];
  for (let i = 0; i < 65; i += 16) {
    const chunk = arr.slice(i, Math.min(i + 16, 65));
    parts.push(
      "    " +
        Array.from(chunk)
          .map((b) => "0x" + b.toString(16).padStart(2, "0"))
          .join(", ") +
        ",",
    );
  }
  return parts.join("\n");
}

const hashes = HASHES_HEX.map((h) => {
  const hex = h.replace(/[^0-9a-fA-F]/g, "").slice(0, 64);
  if (hex.length !== 64)
    throw new Error(
      `Hash must be 64 hex chars, got ${hex.length}: ${hex.slice(0, 20)}...`,
    );
  return Buffer.from(hex, "hex");
});
const parsed = DER_SIGS.map((der) => {
  const { sigR, sigS } = parseDer(der.trim());
  const sNorm = normalizeS(sigS);
  return { sigR, sigS: sNorm, sigSRaw: sigS };
});

// Use normalized S for all recoveries (same as contract).
// Empirically find Chip 1 key: try each of sig 0, 1, 2 as anchor; for each recovery ID get P and check other two recover to P.
function findChip1Key() {
  const indices = [0, 1, 2];
  for (const anchor of indices) {
    const others = indices.filter((i) => i !== anchor);
    for (let rid = 0; rid <= 3; rid++) {
      try {
        const P = recoverPubKeyWithRid(
          hashes[anchor],
          parsed[anchor].sigR,
          parsed[anchor].sigS,
          rid,
        );
        let allMatch = true;
        for (const i of others) {
          let match = false;
          for (let r = 0; r <= 3; r++) {
            try {
              if (
                recoverPubKeyWithRid(
                  hashes[i],
                  parsed[i].sigR,
                  parsed[i].sigS,
                  r,
                ).equals(P)
              ) {
                match = true;
                break;
              }
            } catch (_) {}
          }
          if (!match) {
            allMatch = false;
            break;
          }
        }
        if (allMatch) return P;
      } catch (_) {}
    }
  }
  return null;
}
const chip1 = findChip1Key();
if (!chip1)
  throw new Error(
    "Could not find Chip 1 public key consistent with sigs 0, 1, 2",
  );

// Empirically find Chip 2 key: try sig 3 or sig 4 as anchor; for each recovery ID get P and check the other recovers to P.
function findChip2Key() {
  for (const anchor of [3, 4]) {
    const other = anchor === 3 ? 4 : 3;
    for (let rid = 0; rid <= 3; rid++) {
      try {
        const P = recoverPubKeyWithRid(
          hashes[anchor],
          parsed[anchor].sigR,
          parsed[anchor].sigS,
          rid,
        );
        for (let r = 0; r <= 3; r++) {
          try {
            if (
              recoverPubKeyWithRid(
                hashes[other],
                parsed[other].sigR,
                parsed[other].sigS,
                r,
              ).equals(P)
            )
              return P;
          } catch (_) {}
        }
      } catch (_) {}
    }
  }
  return null;
}
const chip2 = findChip2Key();
if (!chip2)
  throw new Error("Could not find Chip 2 public key consistent with sigs 3, 4");

console.log(
  "// Recovered Chip 1 and Chip 2 public keys and normalized sig_r/sig_s",
);
console.log("// Paste into contracts/nfc-nft/src/test.rs\n");
console.log("const CHIP1_PUBLIC_KEY: [u8; 65] = [");
console.log(fmt65Rust(chip1));
console.log("];\n");
console.log("const CHIP2_PUBLIC_KEY: [u8; 65] = [");
console.log(fmt65Rust(chip2));
console.log("];\n");

console.log(
  "// For each of the 5 TestSignature entries, replace sig_r and sig_s:\n",
);
for (let i = 0; i < 5; i++) {
  console.log(`// --- Signature ${i + 1} ---`);
  console.log("        sig_r: [");
  console.log(fmtRustBytes(parsed[i].sigR));
  console.log("        ],");
  console.log("        sig_s: [");
  console.log(fmtRustBytes(parsed[i].sigS));
  console.log("        ],");
  console.log("");
}
console.log(
  "// → Paste into contracts/nfc-nft/src/test.rs. See dapp/scripts/REGENERATE_NFC_TEST_SIGS.md for exact replacement rules.",
);
