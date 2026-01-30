/**
 * Mint Section Component
 * Handles NFT minting with NFC chip authentication
 */

import { useState } from "react";
import { Button, Text, Code } from "@stellar/design-system";
import { Box } from "../layout/Box.tsx";
import { OperationProgress } from "../OperationProgress.tsx";
import { useWallet } from "../../hooks/useWallet.ts";
import { useNFC } from "../../hooks/useNFC.ts";
import { useChipAuth } from "../../hooks/useChipAuth.ts";
import { useContractClient } from "../../hooks/useContractClient.ts";
import { useOperationSteps } from "../../hooks/useOperationSteps.ts";
import { useErrorHandler } from "../../hooks/useErrorHandler.ts";
import { createSEP53Message } from "../../util/crypto.ts";
import { getNetworkPassphrase } from "../../contracts/util.ts";
import type { ContractCallOptions } from "../../types/contract.ts";

type MintStep =
  | "reading"
  | "signing"
  | "recovering"
  | "calling"
  | "submitting"
  | "confirming"
  | "writing-ndef";

interface MintSectionProps {
  keyId: string;
  contractId: string;
}

interface MintResult {
  success: boolean;
  tokenId?: string;
  publicKey?: string;
  contractId?: string;
  ndefWriteSuccess?: boolean;
  error?: string;
}

const MINT_STEP_DEFINITIONS: Record<
  MintStep,
  { message: string; category: "chip" | "blockchain" | "other" }
> = {
  reading: { message: "Reading chip public key...", category: "chip" },
  signing: { message: "Waiting for chip signature...", category: "chip" },
  recovering: { message: "Determining recovery ID...", category: "chip" },
  calling: { message: "Preparing transaction...", category: "blockchain" },
  submitting: { message: "Sending to blockchain...", category: "blockchain" },
  confirming: { message: "Confirming transaction...", category: "blockchain" },
  "writing-ndef": { message: "Writing NDEF URL to chip...", category: "chip" },
};

const MINT_STEPS: MintStep[] = [
  "reading",
  "signing",
  "recovering",
  "calling",
  "submitting",
  "confirming",
  "writing-ndef",
];

const CHIP_STEPS = MINT_STEPS.filter(
  (step) => MINT_STEP_DEFINITIONS[step].category === "chip",
);
const BLOCKCHAIN_STEPS = MINT_STEPS.filter(
  (step) => MINT_STEP_DEFINITIONS[step].category === "blockchain",
);

export const MintSection = ({ keyId, contractId }: MintSectionProps) => {
  const {
    address,
    updateBalances,
    signTransaction,
    network: walletNetwork,
    networkPassphrase: walletPassphrase,
  } = useWallet();
  const { connected, connect, writeNDEF } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const { handleError } = useErrorHandler();
  const [minting, setMinting] = useState(false);
  const [result, setResult] = useState<MintResult>();

  const {
    currentStep: mintStep,
    setStep: setMintStep,
    clearStep,
    getStepMessage,
    isChipOperation,
    isBlockchainOperation,
  } = useOperationSteps(MINT_STEPS, MINT_STEP_DEFINITIONS);

  const handleMint = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error(
        "Contract client is not ready. Please check your contract ID.",
      );
    }

    // Set UI state FIRST to ensure it renders immediately
    setMinting(true);
    setResult(undefined);
    setMintStep("reading");

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

      // Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(
        walletNetwork,
        walletPassphrase,
      );
      const nonce = 1; // Mint uses nonce = 1

      // Create SEP-53 message
      const { message, messageHash } = await createSEP53Message(
        contractId,
        "mint",
        [address],
        nonce,
        networkPassphraseToUse,
      );

      // Proceed with chip operations
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Chip operations complete - close scanning UI
      // Now move to blockchain operations
      setMintStep("calling");
      const tx = await contractClient.mint(
        {
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
      setMintStep("submitting");
      const txResponse = await tx.signAndSend({ signTransaction, force: true });

      setMintStep("confirming");
      // Wait a moment for confirmation
      await new Promise((resolve) => setTimeout(resolve, 1000));

      // Contract returns u64 token_id (bigint)
      const returnedTokenId = txResponse.result as bigint;
      const tokenIdString = returnedTokenId.toString();

      // Write NDEF URL to chip after successful mint
      setMintStep("writing-ndef");
      let ndefWriteSuccess = false;
      try {
        const ndefUrl = `https://nft.chimpdao.xyz/${contractId}/${tokenIdString}`;
        await writeNDEF(ndefUrl);
        ndefWriteSuccess = true;
      } catch (ndefError) {
        // NDEF write failed but mint was successful, silently continue
      }

      setResult({
        success: true,
        tokenId: tokenIdString,
        publicKey: authResult.publicKey,
        contractId: contractId,
        ndefWriteSuccess,
      });

      await updateBalances();
    } catch (err) {
      console.error("Minting error:", err);
      const errorInfo = handleError(err);
      setResult({
        success: false,
        error: errorInfo.message,
      });
    } finally {
      setMinting(false);
      clearStep();
    }
  };

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to mint NFTs with NFC chip
      </Text>
    );
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void handleMint();
      }}
    >
      {result?.success ? (
        <Box gap="md">
          <Text as="p" size="lg" style={{ color: "#4caf50" }}>
            ✓ NFC Signature Verified!
          </Text>
          <Text
            as="p"
            size="sm"
            weight="semi-bold"
            style={{ marginTop: "12px" }}
          >
            Chip Public Key (Token ID):
          </Text>
          <Code
            size="sm"
            style={{
              wordBreak: "break-all",
              display: "block",
              padding: "8px",
              backgroundColor: "#f5f5f5",
            }}
          >
            {result.publicKey}
          </Code>
          <Text as="p" size="xs" style={{ marginTop: "8px", color: "#666" }}>
            This 65-byte public key is the NFT token ID. The NFT has been
            successfully minted to your wallet.
          </Text>
          {result.ndefWriteSuccess && (
            <Text
              as="p"
              size="xs"
              style={{ marginTop: "8px", color: "#4caf50" }}
            >
              ✓ NDEF URL written to chip: https://nft.chimpdao.xyz/
              {result.contractId}/{result.tokenId}
            </Text>
          )}
          {result.ndefWriteSuccess === false && (
            <Text
              as="p"
              size="xs"
              style={{ marginTop: "8px", color: "#ff9800" }}
            >
              ⚠️ Mint successful, but NDEF URL could not be written to chip
              (chip may be locked or read-only)
            </Text>
          )}
          <Button
            type="button"
            variant="secondary"
            size="md"
            onClick={() => {
              setResult(undefined);
            }}
            style={{ marginTop: "12px" }}
          >
            Mint Again
          </Button>
        </Box>
      ) : result?.error ? (
        <Box gap="md">
          <Text as="p" size="lg" style={{ color: "#d32f2f" }}>
            ✗ Minting Failed
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
        <Box gap="sm" direction="column">
          <Button
            type="submit"
            disabled={minting || !isReady}
            isLoading={minting}
            style={{ marginTop: "12px" }}
            variant="primary"
            size="md"
          >
            Mint NFT with Chip
          </Button>

          {minting && mintStep && (
            <>
              {isChipOperation(mintStep) && (
                <OperationProgress
                  step={mintStep}
                  stepMessage={getStepMessage(mintStep)}
                  steps={CHIP_STEPS}
                  type="chip"
                />
              )}
              {isBlockchainOperation(mintStep) && (
                <OperationProgress
                  step={mintStep}
                  stepMessage={getStepMessage(mintStep)}
                  steps={BLOCKCHAIN_STEPS}
                  type="blockchain"
                />
              )}
              {mintStep === "writing-ndef" && (
                <Box
                  gap="xs"
                  style={{
                    marginTop: "12px",
                    padding: "12px",
                    backgroundColor: "#f5f5f5",
                    borderRadius: "4px",
                  }}
                >
                  <Text
                    as="p"
                    size="sm"
                    weight="semi-bold"
                    style={{ color: "#333" }}
                  >
                    {getStepMessage(mintStep)}
                  </Text>
                </Box>
              )}
            </>
          )}
        </Box>
      )}
    </form>
  );
};
