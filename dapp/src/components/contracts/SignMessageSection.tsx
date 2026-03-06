/**
 * Sign Message Section Component
 * Sign arbitrary text with the NFC chip using the same payload format as the contract
 * (message || signer_xdr || nonce_xdr). Outputs Makefile-ready hex values.
 */

import { useState } from "react";
import { Button, Text, Code, Input } from "@stellar/design-system";
import { Box } from "../layout/Box.tsx";
import { ChipProgressIndicator } from "../ChipProgressIndicator.tsx";
import { useWallet } from "../../hooks/useWallet.ts";
import { useNFC } from "../../hooks/useNFC.ts";
import { useChipAuth } from "../../hooks/useChipAuth.ts";
import { useContractClient } from "../../hooks/useContractClient.ts";
import {
  createChipSignedPayloadHash,
  bytesToHex,
  hexToBytes,
  parseDerSignatureToRaw,
  determineRecoveryId,
} from "../../util/crypto.ts";
import {
  handleChipError,
  formatChipError,
} from "../../util/chipErrorHandler.ts";
import type { ContractCallOptions } from "../../types/contract.ts";

interface SignMessageSectionProps {
  keyId: string;
  contractId: string;
}

interface SignResult {
  message_hex: string;
  nonce: number;
  public_key_hex: string;
  signature_hex: string;
  recovery_id: number;
}

function CopyButton({ value, label }: { value: string; label: string }) {
  const [copied, setCopied] = useState(false);
  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // ignore
    }
  };
  return (
    <Button
      type="button"
      variant="secondary"
      size="sm"
      onClick={handleCopy}
      style={{ marginLeft: "8px" }}
    >
      {copied ? "Copied" : label}
    </Button>
  );
}

export const SignMessageSection = ({
  keyId,
  contractId,
}: SignMessageSectionProps) => {
  const { address } = useWallet();
  const { connected, connect, readChip } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const [messageText, setMessageText] = useState("");
  const [nonceOverride, setNonceOverride] = useState("");
  const [signing, setSigning] = useState(false);
  const [result, setResult] = useState<SignResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hashCopied, setHashCopied] = useState(false);
  const [iosDerSignature, setIosDerSignature] = useState("");
  const [iosPublicKeyHex, setIosPublicKeyHex] = useState("");
  const [iosApplying, setIosApplying] = useState(false);

  const handleCopyHash = async () => {
    if (!address) return;
    if (!messageText.trim()) {
      setError("Enter a message first");
      return;
    }
    setError(null);
    try {
      let nonce: number;
      if (nonceOverride.trim()) {
        nonce = parseInt(nonceOverride, 10);
        if (isNaN(nonce) || nonce < 0) {
          setError("Nonce must be a non-negative integer");
          return;
        }
      } else if (isReady && contractClient) {
        try {
          const keyIdNum = parseInt(keyId, 10);
          if (isNaN(keyIdNum) || keyIdNum < 1 || keyIdNum > 255) {
            setError("Set nonce manually or use a valid Key ID for auto nonce");
            return;
          }
          if (!connected) await connect();
          const chipPublicKeyHex = await readChip(keyIdNum);
          const chipPublicKeyBytes = hexToBytes(chipPublicKeyHex);
          const nonceResult = await contractClient.get_nonce(
            { public_key: Buffer.from(chipPublicKeyBytes) },
            { publicKey: address } as ContractCallOptions,
          );
          const currentNonce = (nonceResult.result as number) || 0;
          nonce = currentNonce + 1;
        } catch {
          setError("Enter nonce manually (could not fetch from contract)");
          return;
        }
      } else {
        setError("Enter nonce (or connect contract to auto-fetch)");
        return;
      }
      const messageBytes = new TextEncoder().encode(messageText.trim());
      const { hash } = await createChipSignedPayloadHash(
        messageBytes,
        address,
        nonce,
      );
      const hashHex = bytesToHex(hash);
      await navigator.clipboard.writeText(hashHex);
      setHashCopied(true);
      setTimeout(() => setHashCopied(false), 2500);
    } catch (err) {
      console.error("Copy hash error:", err);
      setError(err instanceof Error ? err.message : "Failed to copy hash");
    }
  };

  const handleUseIosSignature = async () => {
    if (!address) return;
    if (!messageText.trim()) {
      setError("Enter the same message you signed on iOS");
      return;
    }
    if (!iosDerSignature.trim()) {
      setError("Paste the DER signature from the iOS app");
      return;
    }
    if (!iosPublicKeyHex.trim()) {
      setError("Enter the chip public key (65 bytes hex from iOS or dapp)");
      return;
    }
    setError(null);
    setIosApplying(true);
    try {
      let nonce: number;
      if (nonceOverride.trim()) {
        nonce = parseInt(nonceOverride, 10);
        if (isNaN(nonce) || nonce < 0) {
          setError("Nonce must be a non-negative integer");
          return;
        }
      } else {
        setError("Enter the nonce you used when signing on iOS");
        return;
      }
      const messageBytes = new TextEncoder().encode(messageText.trim());
      const { hash } = await createChipSignedPayloadHash(
        messageBytes,
        address,
        nonce,
      );
      const rawSig = parseDerSignatureToRaw(iosDerSignature.trim());
      let pubKeyHex = iosPublicKeyHex.trim().replace(/^0x/, "");
      if (pubKeyHex.length === 128 && !pubKeyHex.startsWith("04")) {
        pubKeyHex = `04${pubKeyHex}`;
      }
      const recoveryId = await determineRecoveryId(hash, rawSig, pubKeyHex);
      setResult({
        message_hex: bytesToHex(messageBytes),
        nonce,
        public_key_hex: pubKeyHex,
        signature_hex: bytesToHex(rawSig),
        recovery_id: recoveryId,
      });
    } catch (err) {
      console.error("Use iOS signature error:", err);
      setError(err instanceof Error ? err.message : "Invalid signature or key");
    } finally {
      setIosApplying(false);
    }
  };

  const handleSign = async () => {
    if (!address) return;
    if (!messageText.trim()) {
      setError("Enter a message to sign");
      return;
    }
    if (!isReady || !contractClient) {
      setError("Contract client not ready. Check contract ID.");
      return;
    }

    setSigning(true);
    setResult(null);
    setError(null);

    try {
      if (!connected) {
        await connect();
      }

      const keyIdNum = parseInt(keyId, 10);
      if (isNaN(keyIdNum) || keyIdNum < 1 || keyIdNum > 255) {
        throw new Error("Key ID must be between 1 and 255");
      }

      const messageBytes = new TextEncoder().encode(messageText.trim());

      const chipPublicKeyHex = await readChip(keyIdNum);
      const chipPublicKeyBytes = hexToBytes(chipPublicKeyHex);

      let currentNonce = 0;
      try {
        const nonceResult = await contractClient.get_nonce(
          { public_key: Buffer.from(chipPublicKeyBytes) },
          { publicKey: address } as ContractCallOptions,
        );
        currentNonce = (nonceResult.result as number) || 0;
      } catch {
        currentNonce = 0;
      }

      const nonce = nonceOverride.trim()
        ? parseInt(nonceOverride, 10)
        : currentNonce + 1;
      if (isNaN(nonce) || nonce < 0) {
        throw new Error("Nonce must be a non-negative integer");
      }

      const { hash } = await createChipSignedPayloadHash(
        messageBytes,
        address,
        nonce,
      );

      const authResult = await authenticateWithChip(keyIdNum, hash);

      const signatureHex = bytesToHex(new Uint8Array(authResult.signature));
      const publicKeyHex = authResult.publicKey;

      setResult({
        message_hex: bytesToHex(messageBytes),
        nonce,
        public_key_hex: publicKeyHex,
        signature_hex: signatureHex,
        recovery_id: authResult.recoveryId,
      });
    } catch (err) {
      console.error("Sign error:", err);
      const errorResult = handleChipError(err);
      setError(formatChipError(errorResult));
    } finally {
      setSigning(false);
    }
  };

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to sign messages with the NFC chip
      </Text>
    );
  }

  return (
    <Box gap="md" direction="column">
      <Text as="p" size="sm" style={{ color: "#666" }}>
        Enter arbitrary text. The payload signed by the chip is message ||
        signer_xdr || nonce_xdr (same as the contract). Suggested nonce is
        fetched from the contract when you sign.
      </Text>

      <Box gap="xs" direction="column" style={{ maxWidth: "560px" }}>
        <Text as="p" size="sm" weight="semi-bold">
          Message (arbitrary text)
        </Text>
        <textarea
          id="sign-message-input"
          value={messageText}
          onChange={(e) => setMessageText(e.target.value)}
          placeholder="e.g. toto"
          style={{
            minHeight: "80px",
            resize: "vertical",
            padding: "8px 12px",
            borderRadius: "4px",
            border: "1px solid #ccc",
            fontFamily: "inherit",
            fontSize: "14px",
          }}
        />
      </Box>

      <Box gap="xs" direction="column" style={{ maxWidth: "200px" }}>
        <Text as="p" size="sm" weight="semi-bold">
          Nonce (optional override)
        </Text>
        <Input
          id="sign-nonce-input"
          type="number"
          min="0"
          value={nonceOverride}
          onChange={(e) => setNonceOverride(e.target.value)}
          placeholder="auto from contract"
          fieldSize="md"
        />
      </Box>

      <Box gap="sm" direction="row" style={{ alignItems: "center", flexWrap: "wrap" }}>
        <Button
          type="button"
          variant="primary"
          size="md"
          onClick={() => void handleSign()}
          disabled={signing || !messageText.trim()}
          isLoading={signing}
        >
          Sign with chip
        </Button>
        <Button
          type="button"
          variant="secondary"
          size="md"
          onClick={() => void handleCopyHash()}
          disabled={signing || !messageText.trim()}
        >
          {hashCopied ? "Hash copied" : "Copy hash (for iOS)"}
        </Button>
        {signing && (
          <ChipProgressIndicator
            step="scanning"
            stepMessage="Place chip on reader to sign..."
            steps={["scanning"]}
          />
        )}
      </Box>

      <Box
        gap="md"
        direction="column"
        style={{
          marginTop: "16px",
          padding: "16px",
          backgroundColor: "#f5f5f5",
          borderRadius: "8px",
          border: "1px solid #e0e0e0",
        }}
      >
        <Text as="p" size="sm" weight="semi-bold">
          Or use signature from iOS app
        </Text>
        <Text as="p" size="sm" style={{ color: "#666" }}>
          Paste the DER signature and chip public key from the iOS app after
          signing the hash you copied above (64-char hex = sign hash directly).
        </Text>
        <Box gap="xs" direction="column" style={{ maxWidth: "560px" }}>
          <Text as="p" size="sm" weight="semi-bold">
            DER signature (hex)
          </Text>
          <textarea
            id="sign-ios-der-input"
            value={iosDerSignature}
            onChange={(e) => setIosDerSignature(e.target.value)}
            placeholder="e.g. 3045022100..."
            style={{
              minHeight: "56px",
              resize: "vertical",
              padding: "8px 12px",
              borderRadius: "4px",
              border: "1px solid #ccc",
              fontFamily: "monospace",
              fontSize: "12px",
            }}
          />
        </Box>
        <Box gap="xs" direction="column" style={{ maxWidth: "560px" }}>
          <Text as="p" size="sm" weight="semi-bold">
            Chip public key (65 bytes hex, with or without 04 prefix)
          </Text>
          <textarea
            id="sign-ios-pubkey-input"
            value={iosPublicKeyHex}
            onChange={(e) => setIosPublicKeyHex(e.target.value)}
            placeholder="e.g. 04..."
            style={{
              minHeight: "56px",
              resize: "vertical",
              padding: "8px 12px",
              borderRadius: "4px",
              border: "1px solid #ccc",
              fontFamily: "monospace",
              fontSize: "12px",
            }}
          />
        </Box>
        <Button
          type="button"
          variant="secondary"
          size="md"
          onClick={() => void handleUseIosSignature()}
          disabled={
            iosApplying ||
            !messageText.trim() ||
            !nonceOverride.trim() ||
            !iosDerSignature.trim() ||
            !iosPublicKeyHex.trim()
          }
          isLoading={iosApplying}
        >
          Use iOS signature
        </Button>
      </Box>

      {error && (
        <Box gap="sm" style={{ marginTop: "12px" }}>
          <Text as="p" size="md" style={{ color: "#d32f2f" }}>
            {error}
          </Text>
          <Button
            type="button"
            variant="secondary"
            size="sm"
            onClick={() => setError(null)}
          >
            Dismiss
          </Button>
        </Box>
      )}

      {result && (
        <Box
          gap="md"
          direction="column"
          style={{
            marginTop: "16px",
            padding: "16px",
            backgroundColor: "#f9f9f9",
            borderRadius: "8px",
            border: "1px solid #e0e0e0",
          }}
        >
          <Text as="p" size="lg" weight="semi-bold">
            Outputs
          </Text>

          {(
            [
              ["message_hex (--message)", result.message_hex],
              ["nonce", String(result.nonce)],
              ["public_key_hex (--public_key)", result.public_key_hex],
              ["signature_hex (--signature)", result.signature_hex],
              ["recovery_id (--recovery_id)", String(result.recovery_id)],
            ] as const
          ).map(([label, value]) => (
            <Box
              key={label}
              gap="xs"
              direction="column"
              style={{ marginBottom: "8px" }}
            >
              <Text as="p" size="sm" weight="semi-bold">
                {label}
              </Text>
              <Box gap="xs" direction="row" style={{ alignItems: "center" }}>
                <Code
                  size="sm"
                  style={{
                    wordBreak: "break-all",
                    flex: 1,
                    padding: "8px",
                    backgroundColor: "#fff",
                  }}
                >
                  {value}
                </Code>
                <CopyButton value={value} label="Copy" />
              </Box>
            </Box>
          ))}

          <Button
            type="button"
            variant="secondary"
            size="md"
            onClick={() => {
              setResult(null);
              setError(null);
            }}
            style={{ marginTop: "12px" }}
          >
            Sign again
          </Button>
        </Box>
      )}
    </Box>
  );
};
