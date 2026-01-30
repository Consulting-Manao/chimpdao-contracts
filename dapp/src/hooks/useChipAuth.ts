/**
 * useChipAuth Hook
 * Reusable hook for chip signature authentication pattern
 * Used by both mint and transfer operations
 */

import { useNFC } from "./useNFC.ts";
import { hexToBytes, determineRecoveryId } from "../util/crypto.ts";

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
    messageHash: Uint8Array | string,
  ): Promise<ChipAuthResult> => {
    if (!connected) {
      await connect();
    }

    if (isNaN(keyId) || keyId < 1 || keyId > 255) {
      throw new Error("Key ID must be between 1 and 255");
    }

    const messageHashBytes =
      typeof messageHash === "string" ? hexToBytes(messageHash) : messageHash;

    if (messageHashBytes.length !== 32) {
      throw new Error(
        `Invalid message hash length: expected 32 bytes, got ${messageHashBytes.length} bytes`,
      );
    }

    const chipPublicKey = await readChip(keyId);
    const signatureResult = await signWithChip(messageHashBytes, keyId);
    const { signatureBytes } = signatureResult;

    if (signatureBytes.length !== 64) {
      throw new Error(
        `Invalid signature length: expected 64 bytes, got ${signatureBytes.length} bytes`,
      );
    }

    let recoveryId: number;
    try {
      recoveryId = await determineRecoveryId(
        messageHashBytes,
        signatureBytes,
        chipPublicKey,
      );
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      throw new Error(`Could not determine recovery ID: ${errorMsg}`);
    }

    if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
      throw new Error(
        `Invalid recovery ID: ${recoveryId}. Must be an integer between 0 and 3.`,
      );
    }

    const chipPublicKeyBytes = hexToBytes(chipPublicKey);

    if (chipPublicKeyBytes.length !== 65) {
      throw new Error(
        `Invalid public key length: expected 65 bytes (uncompressed), got ${chipPublicKeyBytes.length} bytes`,
      );
    }
    if (chipPublicKeyBytes[0] !== 0x04) {
      throw new Error(
        `Invalid public key format: expected uncompressed key (starting with 0x04), got 0x${chipPublicKeyBytes[0].toString(16).padStart(2, "0")}`,
      );
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
