/**
 * Parse DER-encoded ECDSA signature to extract r and s values.
 * @param {string} derHex - DER-encoded signature as hex string
 * @returns {{r: string, s: string, wasNormalized: boolean}} - r and s as hex strings (32 bytes each), and whether s was normalized
 */
export function parseDERSignature(derHex) {
  const der = Buffer.from(derHex, "hex");
  let offset = 0;

  // 0x30: SEQUENCE
  if (der[offset++] !== 0x30) throw new Error("Invalid DER: not a SEQUENCE");
  offset++; // Skip total length

  // 0x02: INTEGER (r)
  if (der[offset++] !== 0x02) throw new Error("Invalid DER: r not an INTEGER");
  const rLength = der[offset++];
  const rBytes = der.slice(offset, offset + rLength);
  offset += rLength;

  // 0x02: INTEGER (s)
  if (der[offset++] !== 0x02) throw new Error("Invalid DER: s not an INTEGER");
  const sLength = der[offset++];
  let sBytes = der.slice(offset, offset + sLength);

  // Remove leading 0x00 if present (DER adds it when high bit is set)
  const rClean = rBytes[0] === 0x00 ? rBytes.slice(1) : rBytes;
  let sClean = sBytes[0] === 0x00 ? sBytes.slice(1) : sBytes;

  // Normalize s to low form (required by Stellar/Soroban)
  // secp256k1 curve order: n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  const CURVE_ORDER = Buffer.from(
    "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
    "hex",
  );
  const HALF_CURVE_ORDER = Buffer.from(
    "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0",
    "hex",
  );

  // Convert to BigInt for comparison
  const sBigInt = BigInt("0x" + sClean.toString("hex"));
  const halfOrderBigInt = BigInt("0x" + HALF_CURVE_ORDER.toString("hex"));
  const orderBigInt = BigInt("0x" + CURVE_ORDER.toString("hex"));

  // Track if s was normalized (s > n/2)
  const wasNormalized = sBigInt > halfOrderBigInt;

  // If s > n/2, then s = n - s
  if (wasNormalized) {
    const sNormalized = orderBigInt - sBigInt;
    sClean = Buffer.from(sNormalized.toString(16).padStart(64, "0"), "hex");
  }

  // Pad to 32 bytes
  const rPadded = Buffer.alloc(32);
  rClean.copy(rPadded, 32 - rClean.length);
  const sPadded = Buffer.alloc(32);
  sClean.copy(sPadded, 32 - sClean.length);

  return {
    r: rPadded.toString("hex"),
    s: sPadded.toString("hex"),
    wasNormalized,
  };
}
