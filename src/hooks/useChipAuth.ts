/**
 * useChipAuth Hook
 * Reusable hook for chip signature authentication pattern
 * Used by both mint and transfer operations
 */

import { useNFC } from "./useNFC";
import { hexToBytes, determineRecoveryId } from "../util/crypto";

export interface ChipAuthResult {
  publicKey: string;
  publicKeyBytes: Buffer;
  signature: Buffer;
  recoveryId: number;
}

export const useChipAuth = () => {
  const { readChip, signWithChip, connect, connected } = useNFC();

  const authenticateWithChip = async (
    keyId: number,
    messageHash: string
  ): Promise<ChipAuthResult> => {
    // Ensure we're connected to NFC server
    if (!connected) {
      await connect();
    }

    // Validate keyId
    if (isNaN(keyId) || keyId < 1 || keyId > 255) {
      throw new Error('Key ID must be between 1 and 255');
    }

    // 1. Read chip's public key
    const chipPublicKey = await readChip(keyId);

    // 2. NFC chip signs the hash
    const signatureResult = await signWithChip(messageHash, keyId);
    const { signatureBytes } = signatureResult;

    // 3. Determine recovery ID by trying all 4 possibilities (0-3)
    const recoveryId = await determineRecoveryId(messageHash, signatureBytes, chipPublicKey);

    // Ensure recoveryId is a valid integer between 0 and 3
    if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
      throw new Error(`Invalid recovery ID: ${recoveryId}. Must be an integer between 0 and 3.`);
    }

    // Convert chip's public key (hex string) to bytes for passing to contract
    const chipPublicKeyBytes = hexToBytes(chipPublicKey);

    // Validate public key format (must be 65 bytes, uncompressed, starting with 0x04)
    if (chipPublicKeyBytes.length !== 65) {
      throw new Error(`Invalid public key length: expected 65 bytes (uncompressed), got ${chipPublicKeyBytes.length} bytes`);
    }
    if (chipPublicKeyBytes[0] !== 0x04) {
      throw new Error(`Invalid public key format: expected uncompressed key (starting with 0x04), got 0x${chipPublicKeyBytes[0].toString(16).padStart(2, '0')}`);
    }

    return {
      publicKey: chipPublicKey,
      publicKeyBytes: Buffer.from(chipPublicKeyBytes),
      signature: Buffer.from(signatureBytes),
      recoveryId,
    };
  };

  return { authenticateWithChip };
};
