/**
 * Claim Section Component
 * Handles NFT claiming with NFC chip authentication
 */

import { useState } from "react";
import { Button, Text } from "@stellar/design-system";
import { Box } from "../layout/Box.tsx";
import { ChipProgressIndicator } from "../ChipProgressIndicator.tsx";
import { useWallet } from "../../hooks/useWallet.ts";
import { useNFC } from "../../hooks/useNFC.ts";
import { useChipAuth } from "../../hooks/useChipAuth.ts";
import { useContractClient } from "../../hooks/useContractClient.ts";
import { createSEP53Message } from "../../util/crypto.ts";
import { getNetworkPassphrase } from "../../contracts/util.ts";
import {
  handleChipError,
  formatChipError,
} from "../../util/chipErrorHandler.ts";
import type { ContractCallOptions } from "../../types/contract.ts";

type ClaimStep =
  | "idle"
  | "reading"
  | "signing"
  | "recovering"
  | "calling"
  | "confirming";

interface ClaimSectionProps {
  keyId: string;
  contractId: string;
}

interface ClaimResult {
  success: boolean;
  tokenId?: string;
  error?: string;
}

export const ClaimSection = ({ keyId, contractId }: ClaimSectionProps) => {
  const {
    address,
    updateBalances,
    signTransaction,
    network: walletNetwork,
    networkPassphrase: walletPassphrase,
  } = useWallet();
  const { connected, connect, readChip } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const [claiming, setClaiming] = useState(false);
  const [claimStep, setClaimStep] = useState<ClaimStep>("idle");
  const [result, setResult] = useState<ClaimResult>();

  const steps: ClaimStep[] = [
    "reading",
    "signing",
    "recovering",
    "calling",
    "confirming",
  ];

  const getStepMessage = (step: ClaimStep): string => {
    switch (step) {
      case "reading":
        return "Reading chip public key...";
      case "signing":
        return "Waiting for chip signature...";
      case "recovering":
        return "Determining recovery ID...";
      case "calling":
        return "Calling contract...";
      case "confirming":
        return "Confirming transaction...";
      default:
        return "Processing...";
    }
  };

  const handleClaim = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error(
        "Contract client is not ready. Please check your contract ID.",
      );
    }

    setClaiming(true);
    setClaimStep("idle");
    setResult(undefined);

    try {
      // Ensure we're connected to NFC server
      if (!connected) {
        setClaimStep("reading");
        await connect();
      }

      // Validate keyId
      const keyIdNum = parseInt(keyId, 10);
      if (isNaN(keyIdNum) || keyIdNum < 1 || keyIdNum > 255) {
        throw new Error("Key ID must be between 1 and 255");
      }

      if (!walletPassphrase) {
        throw new Error("Network passphrase is required");
      }

      // Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(
        walletNetwork,
        walletPassphrase,
      );

      // Read chip public key first to get nonce
      setClaimStep("reading");
      const chipPublicKeyHex = await readChip(keyIdNum);
      const { hexToBytes } = await import("../../util/crypto.ts");
      const chipPublicKeyBytes = hexToBytes(chipPublicKeyHex);

      // Get current nonce from contract
      let currentNonce = 0;
      try {
        const nonceResult = await contractClient.get_nonce(
          {
            public_key: Buffer.from(chipPublicKeyBytes),
          },
          {
            publicKey: address,
          } as ContractCallOptions,
        );
        currentNonce = (nonceResult.result as number) || 0;
      } catch (err) {
        // If get_nonce fails, default to 0
        // Nonce fetch failed, defaulting to 0 (first use)
        currentNonce = 0;
      }

      // Use next nonce (must be greater than stored)
      const nonce = currentNonce + 1;

      // Create SEP-53 message for claim
      const { message, messageHash } = await createSEP53Message(
        contractId,
        "claim",
        [address],
        nonce,
        networkPassphraseToUse,
      );

      // Authenticate with chip
      setClaimStep("signing");
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Call contract
      setClaimStep("calling");
      const tx = await contractClient.claim(
        {
          claimant: address,
          message: Buffer.from(message),
          signature: authResult.signature,
          recovery_id: authResult.recoveryId,
          public_key: authResult.publicKeyBytes,
          nonce: nonce,
        },
        {
          publicKey: address,
        } as ContractCallOptions,
      );

      // Sign and send transaction
      setClaimStep("confirming");
      const txResponse = await tx.signAndSend({ signTransaction, force: true });

      // Contract returns u64 token_id (bigint)
      const returnedTokenId = txResponse.result as bigint;
      const tokenIdString = returnedTokenId.toString();

      setResult({
        success: true,
        tokenId: tokenIdString,
      });

      await updateBalances();
    } catch (err) {
      console.error("Claiming error:", err);
      const errorResult = handleChipError(err);
      setResult({
        success: false,
        error: formatChipError(errorResult),
      });
    } finally {
      setClaiming(false);
      setClaimStep("idle");
    }
  };

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to claim NFTs with NFC chip
      </Text>
    );
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void handleClaim();
      }}
    >
      <Box gap="sm" direction="column">
        {result?.success ? (
          <Box gap="md" style={{ marginTop: "16px" }}>
            <Text as="p" size="lg" style={{ color: "#4caf50" }}>
              ✓ Claim Successful!
            </Text>
            <Text as="p" size="sm" style={{ color: "#666" }}>
              Token {result.tokenId} has been successfully claimed to your
              wallet.
            </Text>
            <Button
              type="button"
              variant="secondary"
              size="md"
              onClick={() => {
                setResult(undefined);
              }}
              style={{ marginTop: "12px" }}
            >
              Claim Another
            </Button>
          </Box>
        ) : result?.error ? (
          <Box gap="md" style={{ marginTop: "16px" }}>
            <Text as="p" size="lg" style={{ color: "#d32f2f" }}>
              ✗ Claim Failed
            </Text>
            <Text as="p" size="sm" style={{ color: "#666" }}>
              {typeof result.error === "string"
                ? result.error
                : String(result.error || "Unknown error")}
            </Text>
            <Button
              type="button"
              variant="secondary"
              size="md"
              onClick={() => setResult(undefined)}
              style={{ marginTop: "8px" }}
            >
              Try Again
            </Button>
          </Box>
        ) : (
          <Box gap="sm" direction="column" style={{ marginTop: "12px" }}>
            <Button
              type="submit"
              disabled={claiming || !isReady}
              isLoading={claiming}
              variant="primary"
              size="md"
            >
              Claim NFT with Chip
            </Button>

            {claiming && claimStep !== "idle" && (
              <ChipProgressIndicator
                step={claimStep}
                stepMessage={getStepMessage(claimStep)}
                steps={steps}
              />
            )}
          </Box>
        )}
      </Box>
    </form>
  );
};
