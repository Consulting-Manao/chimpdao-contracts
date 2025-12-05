/**
 * Crypto utilities for NFC chip signature handling
 * Provides SHA-256 hashing and signature format conversion for Soroban
 */

/**
 * Convert hex string to Uint8Array
 */
export function hexToBytes(hex: string): Uint8Array {
  // Remove 0x prefix if present
  const cleanHex = hex.startsWith('0x') ? hex.slice(2) : hex;
  
  // Ensure even number of characters
  const paddedHex = cleanHex.length % 2 === 0 ? cleanHex : '0' + cleanHex;
  
  const bytes = new Uint8Array(paddedHex.length / 2);
  for (let i = 0; i < paddedHex.length; i += 2) {
    bytes[i / 2] = parseInt(paddedHex.substr(i, 2), 16);
  }
  return bytes;
}

/**
 * Convert Uint8Array to hex string
 */
export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Generate SHA-256 hash of data
 * Uses Web Crypto API (available in modern browsers)
 */
export async function sha256(data: string | Uint8Array): Promise<Uint8Array> {
  const bytes = typeof data === 'string' 
    ? new TextEncoder().encode(data) 
    : data;
  
  const hashBuffer = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return new Uint8Array(hashBuffer);
}

/**
 * SEP-53: Standard Contract Authentication
 * Creates a standard message for contract function authorization
 */
export interface SEP53AuthEntry {
  contractAddress: string;
  functionName: string;
  args: unknown[];
  validUntilLedger: number;
}

/**
 * Create SEP-53 compliant auth message
 * Returns both the message and its hash
 */
export async function createSEP53Message(
  contractId: string,
  functionName: string,
  args: unknown[],
  validUntilLedger: number,
  networkPassphrase: string
): Promise<{ message: Uint8Array; messageHash: Uint8Array }> {
  // SEP-53 format:
  // hash(network_id || contract_id || function_name || args || valid_until_ledger)
  
  const encoder = new TextEncoder();
  const parts: Uint8Array[] = [];
  
  // Network passphrase hash (32 bytes)
  const networkHash = await sha256(encoder.encode(networkPassphrase));
  parts.push(networkHash);
  
  // Contract ID (32 bytes for Stellar addresses)
  const contractIdBytes = hexToBytes(contractId);
  parts.push(contractIdBytes);
  
  // Function name
  const functionNameBytes = encoder.encode(functionName);
  parts.push(functionNameBytes);
  
  // Args (serialized)
  const argsBytes = encoder.encode(JSON.stringify(args));
  parts.push(argsBytes);
  
  // Valid until ledger (4 bytes, big endian)
  const ledgerBytes = new Uint8Array(4);
  const view = new DataView(ledgerBytes.buffer);
  view.setUint32(0, validUntilLedger, false); // big endian
  parts.push(ledgerBytes);
  
  // Concatenate all parts
  const totalLength = parts.reduce((sum, part) => sum + part.length, 0);
  const combined = new Uint8Array(totalLength);
  let offset = 0;
  for (const part of parts) {
    combined.set(part, offset);
    offset += part.length;
  }
  
  // Return both the message and its hash
  // The chip signs the hash, but the contract needs the original message
  const messageHash = await sha256(combined);
  return {
    message: combined,
    messageHash: messageHash
  };
}


/**
 * Format signature from NFC chip for Soroban
 * NFC chip returns (r, s, v) format
 * Soroban expects 64 bytes (r + s concatenated) and separate recovery_id
 */
export interface NFCSignature {
  r: string;  // 32 bytes hex
  s: string;  // 32 bytes hex
  v: number;  // Recovery ID indicator
  recoveryId?: number;
}

export interface SorobanSignature {
  signatureBytes: Uint8Array;  // 64 bytes: r (32) + s (32)
  recoveryId: number;           // 0-3
}

/**
 * Convert NFC chip signature format to Soroban format
 */
export function formatSignatureForSoroban(signature: NFCSignature): SorobanSignature {
  // Convert hex strings to bytes
  const rBytes = hexToBytes(signature.r);
  const sBytes = hexToBytes(signature.s);
  
  // Validate lengths
  if (rBytes.length !== 32) {
    throw new Error(`Invalid r length: ${rBytes.length}, expected 32 bytes`);
  }
  if (sBytes.length !== 32) {
    throw new Error(`Invalid s length: ${sBytes.length}, expected 32 bytes`);
  }
  
  // Concatenate r and s
  const signatureBytes = new Uint8Array(64);
  signatureBytes.set(rBytes, 0);
  signatureBytes.set(sBytes, 32);
  
  // Calculate recovery ID
  // v can be: 0-3 (raw), 27-30 (Ethereum style), or provided explicitly
  let recoveryId: number;
  
  if (signature.recoveryId !== undefined) {
    recoveryId = signature.recoveryId;
  } else if (signature.v >= 27 && signature.v <= 30) {
    // Ethereum-style v value
    recoveryId = signature.v - 27;
  } else if (signature.v >= 0 && signature.v <= 3) {
    // Raw recovery ID
    recoveryId = signature.v;
  } else {
    throw new Error(`Invalid v value: ${signature.v}`);
  }
  
  // Validate recovery ID range
  if (recoveryId < 0 || recoveryId > 3) {
    throw new Error(`Recovery ID out of range: ${recoveryId}, must be 0-3`);
  }
  
  return {
    signatureBytes,
    recoveryId
  };
}

/**
 * Try all recovery IDs (0-3) to find the correct one
 * This is useful when the NFC chip doesn't provide a reliable v value
 * Returns array of recovery IDs to try, sorted by most likely first
 */
export function getPossibleRecoveryIds(v?: number): number[] {
  if (v === undefined) {
    // Try all in order
    return [0, 1, 2, 3];
  }
  
  // Calculate most likely recovery ID
  let primaryId: number;
  if (v >= 27 && v <= 30) {
    primaryId = v - 27;
  } else if (v >= 0 && v <= 3) {
    primaryId = v;
  } else {
    // Unknown v, try all
    return [0, 1, 2, 3];
  }
  
  // Return primary ID first, then others
  const others = [0, 1, 2, 3].filter(id => id !== primaryId);
  return [primaryId, ...others];
}

/**
 * Validate message digest for Soroban
 */
export function validateMessageDigest(digest: Uint8Array): void {
  if (digest.length !== 32) {
    throw new Error(`Invalid message digest length: ${digest.length}, expected 32 bytes`);
  }
}

/**
 * Validate signature for Soroban
 */
export function validateSignature(signature: Uint8Array): void {
  if (signature.length !== 64) {
    throw new Error(`Invalid signature length: ${signature.length}, expected 64 bytes`);
  }
}

/**
 * Fetch the current ledger sequence number from Horizon API
 * 
 * @param horizonUrl - Horizon API base URL
 * @returns Current ledger sequence number
 * @throws Error if unable to fetch ledger
 */
export async function fetchCurrentLedger(horizonUrl: string): Promise<number> {
  try {
    const response = await fetch(`${horizonUrl}/ledgers?order=desc&limit=1`);
    
    if (!response.ok) {
      throw new Error(`Horizon API returned ${response.status}`);
    }
    
    const data = await response.json() as { _embedded?: { records?: Array<{ sequence: string | number }> } };
    
    if (!data._embedded?.records?.[0]?.sequence) {
      throw new Error('Invalid ledger response format');
    }
    
    const sequence = data._embedded.records[0].sequence;
    return typeof sequence === 'string' ? parseInt(sequence, 10) : sequence;
  } catch (error) {
    throw new Error(`Failed to fetch current ledger: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Determine the correct recovery ID by trying all possibilities (0-3)
 * and matching against the expected public key from the NFC chip.
 * 
 * @param messageHash - SHA-256 hash of the message (32 bytes)
 * @param signature - ECDSA signature (64 bytes: r + s)
 * @param expectedPublicKey - Expected public key in hex format (65 bytes uncompressed)
 * @returns The correct recovery ID (0-3)
 * @throws Error if no matching recovery ID found
 */
export async function determineRecoveryId(
  messageHash: Uint8Array,
  signature: Uint8Array,
  expectedPublicKey: string
): Promise<number> {
  if (messageHash.length !== 32) {
    throw new Error(`Invalid message hash length: ${messageHash.length}, expected 32 bytes`);
  }
  if (signature.length !== 64) {
    throw new Error(`Invalid signature length: ${signature.length}, expected 64 bytes`);
  }
  
  // Dynamic import to avoid bundling issues
  const secp256k1 = await import('@noble/secp256k1');
  
  // Convert expected public key to bytes (remove 0x prefix if present)
  const expectedKeyHex = expectedPublicKey.startsWith('0x') 
    ? expectedPublicKey.slice(2) 
    : expectedPublicKey;
  const expectedKeyBytes = hexToBytes(expectedKeyHex);
  
  // Try each recovery ID (0-3)
  for (let recoveryId = 0; recoveryId <= 3; recoveryId++) {
    try {
      // @noble/secp256k1 expects signature in "recovered" format (65 bytes: r + s + recovery_id)
      // Create recovered format signature by appending recovery ID byte
      const recoveredSignature = new Uint8Array(65);
      recoveredSignature.set(signature, 0);
      recoveredSignature[64] = recoveryId;
      
      // Recover public key with this recovery ID
      // API: recoverPublicKey(signature: Bytes, message: Bytes, opts?: ECDSARecoverOpts)
      // Signature must be in "recovered" format (65 bytes)
      // opts.prehash defaults to true (hashes the message), but we already have a hash
      const recoveredKey = secp256k1.recoverPublicKey(
        recoveredSignature, 
        messageHash, 
        { prehash: false } // Message is already hashed
      );
      
      // Compare with expected key (uncompressed format)
      // Convert recovered key to hex for comparison
      const recoveredKeyHex = bytesToHex(recoveredKey);
      const expectedKeyHexClean = bytesToHex(expectedKeyBytes);
      
      if (recoveredKeyHex.toLowerCase() === expectedKeyHexClean.toLowerCase()) {
        return recoveryId;
      }
    } catch {
      // This recovery ID failed, try next one
      continue;
    }
  }
  
  throw new Error('Could not determine recovery ID: no match found after trying all possibilities (0-3)');
}

