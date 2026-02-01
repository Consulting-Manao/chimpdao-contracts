/**
 * Transfer Section Component
 * Handles NFT transfer with NFC chip authentication
 */

import { useState } from "react";
import { Button, Text, Input } from "@stellar/design-system";
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

type TransferStep =
  | "idle"
  | "reading"
  | "signing"
  | "recovering"
  | "calling"
  | "submitting"
  | "confirming";

interface TransferSectionProps {
  keyId: string;
  contractId: string;
}

interface TransferResult {
  success: boolean;
  tokenId?: string;
  error?: string;
}

export const TransferSection = ({
  keyId,
  contractId,
}: TransferSectionProps) => {
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
  const [transferring, setTransferring] = useState(false);
  const [transferStep, setTransferStep] = useState<TransferStep>("idle");
  const [recipientAddress, setRecipientAddress] = useState("");
  const [tokenId, setTokenId] = useState("");
  const [result, setResult] = useState<TransferResult>();

  const chipSteps: TransferStep[] = ["reading", "signing", "recovering"];
  const blockchainSteps: TransferStep[] = [
    "calling",
    "submitting",
    "confirming",
  ];
  const allSteps: TransferStep[] = [...chipSteps, ...blockchainSteps];

  const getStepMessage = (step: TransferStep): string => {
    switch (step) {
      case "reading":
        return "Reading chip public key...";
      case "signing":
        return "Waiting for chip signature...";
      case "recovering":
        return "Determining recovery ID...";
      case "calling":
        return "Preparing transaction...";
      case "submitting":
        return "Sending to blockchain...";
      case "confirming":
        return "Confirming transaction...";
      default:
        return "Processing...";
    }
  };

  const isChipOperation = (step: TransferStep): boolean => {
    return chipSteps.includes(step);
  };

  const isBlockchainOperation = (step: TransferStep): boolean => {
    return blockchainSteps.includes(step);
  };

  const handleTransfer = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error(
        "Contract client is not ready. Please check your contract ID.",
      );
    }

    if (!recipientAddress.trim()) {
      throw new Error("Recipient address is required");
    }

    if (!tokenId.trim()) {
      throw new Error("Token ID is required");
    }

    setTransferring(true);
    setResult(undefined);
    setTransferStep("reading");

    try {
      // Ensure we're connected to NFC server
      if (!connected) {
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

      const tokenIdNum = BigInt(tokenId.trim());

      // Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(
        walletNetwork,
        walletPassphrase,
      );

      // Proceed with chip operations
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

      // Create SEP-53 message for transfer (signer = from = wallet address)
      const { message, messageHash } = await createSEP53Message(
        contractId,
        "transfer",
        [address, recipientAddress.trim(), tokenIdNum.toString()],
        nonce,
        networkPassphraseToUse,
        address,
      );

      // Authenticate with chip
      setTransferStep("signing");
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Chip operations complete - close scanning UI
      // Now move to blockchain operations
      setTransferStep("calling");
      const tx = await contractClient.transfer(
        {
          from: address,
          to: recipientAddress.trim(),
          token_id: tokenIdNum,
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
      setTransferStep("submitting");
      await tx.signAndSend({ signTransaction, force: true });

      setTransferStep("confirming");
      // Wait a moment for confirmation
      await new Promise((resolve) => setTimeout(resolve, 1000));

      setResult({
        success: true,
        tokenId: tokenId,
      });

      await updateBalances();
    } catch (err) {
      console.error("Transfer error:", err);
      const errorResult = handleChipError(err);
      setResult({
        success: false,
        error: formatChipError(errorResult),
      });
    } finally {
      setTransferring(false);
      setTransferStep("idle");
    }
  };

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to transfer NFTs with NFC chip
      </Text>
    );
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void handleTransfer();
      }}
    >
      <Box gap="sm" direction="column">
        <Box gap="xs" direction="column">
          <Text as="p" size="sm" weight="semi-bold">
            Recipient Address
          </Text>
          <Input
            id="recipient-address"
            type="text"
            value={recipientAddress}
            onChange={(e) => setRecipientAddress(e.target.value)}
            placeholder="Enter recipient Stellar address"
            disabled={transferring}
            fieldSize="md"
          />
        </Box>

        <Box gap="xs" direction="column">
          <Text as="p" size="sm" weight="semi-bold">
            Token ID
          </Text>
          <Input
            id="token-id"
            type="text"
            value={tokenId}
            onChange={(e) => setTokenId(e.target.value)}
            placeholder="Enter token ID to transfer"
            disabled={transferring}
            fieldSize="md"
          />
        </Box>

        {result?.success ? (
          <Box gap="md" style={{ marginTop: "16px" }}>
            <Text as="p" size="lg" style={{ color: "#4caf50" }}>
              ✓ Transfer Successful!
            </Text>
            <Text as="p" size="sm" style={{ color: "#666" }}>
              Token {result.tokenId} has been successfully transferred.
            </Text>
            <Button
              type="button"
              variant="secondary"
              size="md"
              onClick={() => {
                setResult(undefined);
                setRecipientAddress("");
                setTokenId("");
              }}
              style={{ marginTop: "12px" }}
            >
              Transfer Another
            </Button>
          </Box>
        ) : result?.error ? (
          <Box gap="md" style={{ marginTop: "16px" }}>
            <Text as="p" size="lg" style={{ color: "#d32f2f" }}>
              ✗ Transfer Failed
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
              disabled={
                transferring ||
                !isReady ||
                !recipientAddress.trim() ||
                !tokenId.trim()
              }
              isLoading={transferring}
              variant="primary"
              size="md"
            >
              Transfer NFT with Chip
            </Button>

            {transferring && (
              <>
                {isChipOperation(transferStep) && (
                  <ChipProgressIndicator
                    step={transferStep}
                    stepMessage={getStepMessage(transferStep)}
                    steps={chipSteps}
                  />
                )}
                {isBlockchainOperation(transferStep) && (
                  <Box
                    gap="xs"
                    style={{
                      marginTop: "12px",
                      padding: "12px",
                      backgroundColor: "#e3f2fd",
                      borderRadius: "4px",
                    }}
                  >
                    <Text
                      as="p"
                      size="sm"
                      weight="semi-bold"
                      style={{ color: "#1976d2" }}
                    >
                      {getStepMessage(transferStep)}
                    </Text>
                    <Box gap="xs" direction="row" style={{ marginTop: "4px" }}>
                      {blockchainSteps.map((stepName) => (
                        <div
                          key={stepName}
                          style={{
                            width: "8px",
                            height: "8px",
                            borderRadius: "50%",
                            backgroundColor:
                              blockchainSteps.indexOf(transferStep) >=
                              blockchainSteps.indexOf(stepName)
                                ? "#1976d2"
                                : "#ddd",
                            transition: "background-color 0.3s ease",
                          }}
                        />
                      ))}
                    </Box>
                  </Box>
                )}
              </>
            )}
          </Box>
        )}
      </Box>
    </form>
  );
};
