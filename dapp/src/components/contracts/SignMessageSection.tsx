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

      <Box gap="sm" direction="row" style={{ alignItems: "center" }}>
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
        {signing && (
          <ChipProgressIndicator
            step="scanning"
            stepMessage="Place chip on reader to sign..."
            steps={["scanning"]}
          />
        )}
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
