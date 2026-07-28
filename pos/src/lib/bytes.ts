export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) throw new Error("odd hex length");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/** raw 32-byte integer → DER INTEGER (0x02 len bytes) */
export function derInt(b: Uint8Array): Uint8Array {
  let v = b;
  while (v.length > 1 && v[0] === 0) v = v.subarray(1);
  const needsPad = (v[0] ?? 0) >= 0x80;
  const bodyLen = needsPad ? v.length + 1 : v.length;
  const out = new Uint8Array(2 + bodyLen);
  out[0] = 0x02;
  out[1] = bodyLen;
  out.set(v, needsPad ? 3 : 2);
  return out;
}

/** 64-byte r||s → DER SEQUENCE hex */
export function derSignature(rs: Uint8Array): string {
  if (rs.length !== 64) {
    throw new Error(`expected 64-byte r||s, got ${rs.length}`);
  }
  const r = derInt(rs.subarray(0, 32));
  const s = derInt(rs.subarray(32));
  const seq = new Uint8Array(2 + r.length + s.length);
  seq[0] = 0x30;
  seq[1] = r.length + s.length;
  seq.set(r, 2);
  seq.set(s, 2 + r.length);
  return bytesToHex(seq).toUpperCase();
}

// ponytail: assert a high-bit integer gets its leading 0x00 pad
if (import.meta.env.DEV) {
  const sample = new Uint8Array(32);
  sample[0] = 0x80;
  const enc = derInt(sample);
  if (enc[0] !== 0x02 || enc[1] !== 33 || enc[2] !== 0) {
    console.warn("der self-check failed", bytesToHex(enc));
  }
}
