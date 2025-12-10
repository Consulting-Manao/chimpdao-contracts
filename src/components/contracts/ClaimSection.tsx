/**
 * Claim Section Component
 * Handles NFT claiming with NFC chip authentication
 */

import { useState } from "react";
import { Button, Text, Code, Input } from "@stellar/design-system";
import { Box } from "../layout/Box";
import { ChipProgressIndicator } from "../ChipProgressIndicator";
import { useWallet } from "../../hooks/useWallet";
import { useNFC } from "../../hooks/useNFC";
import { useChipAuth } from "../../hooks/useChipAuth";
import { useContractClient } from "../../hooks/useContractClient";
import { createSEP53Message } from "../../util/crypto";
import { getNetworkPassphrase } from "../../contracts/util";
import { NFCServerNotRunningError, ChipNotPresentError, APDUCommandFailedError, RecoveryIdError } from "../../util/nfcClient";

type ClaimStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming';

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
  const { address, updateBalances, signTransaction, network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();
  const { connected, connect } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const [claiming, setClaiming] = useState(false);
  const [claimStep, setClaimStep] = useState<ClaimStep>('idle');
  const [tokenId, setTokenId] = useState("");
  const [result, setResult] = useState<ClaimResult>();

  const steps: ClaimStep[] = ['reading', 'signing', 'recovering', 'calling', 'confirming'];

  const getStepMessage = (step: ClaimStep): string => {
    switch (step) {
      case 'reading':
        return 'Reading chip public key...';
      case 'signing':
        return 'Waiting for chip signature...';
      case 'recovering':
        return 'Determining recovery ID...';
      case 'calling':
        return 'Calling contract...';
      case 'confirming':
        return 'Confirming transaction...';
      default:
        return 'Processing...';
    }
  };

  const handleClaim = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error('Contract client is not ready. Please check your contract ID.');
    }

    if (!tokenId.trim()) {
      throw new Error('Token ID is required');
    }

    setClaiming(true);
    setClaimStep('idle');
    setResult(undefined);

    try {
      // Ensure we're connected to NFC server
      if (!connected) {
        setClaimStep('reading');
        await connect();
      }

      // Validate keyId
      const keyIdNum = parseInt(keyId, 10);
      if (isNaN(keyIdNum) || keyIdNum < 1 || keyIdNum > 255) {
        throw new Error('Key ID must be between 1 and 255');
      }

      if (!walletPassphrase) {
        throw new Error('Network passphrase is required');
      }

      const tokenIdNum = BigInt(tokenId.trim());

      // Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(walletNetwork, walletPassphrase);
      
      // Get current nonce for the token (we'll need to fetch this from contract)
      // For now, using 0 - in production, should fetch actual nonce
      const nonce = 0;

      // Create SEP-53 message for claim
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'claim',
        [address, tokenIdNum.toString()],
        nonce,
        networkPassphraseToUse
      );

      // Authenticate with chip
      setClaimStep('reading');
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Call contract
      setClaimStep('calling');
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
        } as any
      );

      // Sign and send transaction
      setClaimStep('confirming');
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
      console.error('Claiming error:', err);

      let errorMessage = "Unknown error";
      let actionableGuidance = "";

      if (err instanceof NFCServerNotRunningError) {
        errorMessage = "NFC Server Not Running";
        actionableGuidance = "Please start the NFC server in a separate terminal with: bun run nfc-server";
      } else if (err instanceof ChipNotPresentError) {
        errorMessage = "No NFC Chip Detected";
        actionableGuidance = "Please place your Infineon NFC chip on the reader and try again.";
      } else if (err instanceof APDUCommandFailedError) {
        errorMessage = "Command Failed";
        actionableGuidance = "The chip may not be properly positioned. Try repositioning the chip on the reader.";
      } else if (err instanceof RecoveryIdError) {
        errorMessage = "Recovery ID Detection Failed";
        actionableGuidance = "This may indicate a signature mismatch. Please try again.";
      } else if (err instanceof Error) {
        errorMessage = err.message || String(err);
        if (err.message?.includes("timeout") || err.message?.includes("Timeout")) {
          actionableGuidance = "The operation took too long. Please ensure the chip is positioned correctly and try again.";
        } else if (err.message?.includes("connection") || err.message?.includes("WebSocket")) {
          actionableGuidance = "Check that the NFC server is running: bun run nfc-server";
        }
      } else {
        // Handle non-Error objects (e.g., transaction objects)
        errorMessage = String(err) || "Unknown error occurred";
      }

      setResult({
        success: false,
        error: actionableGuidance ? `${errorMessage}\n\n${actionableGuidance}` : errorMessage,
      });
    } finally {
      setClaiming(false);
      setClaimStep('idle');
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
        <Box gap="xs" direction="column">
          <Text as="p" size="sm" weight="semi-bold">
            Token ID
          </Text>
          <Input
            type="text"
            value={tokenId}
            onChange={(e) => setTokenId(e.target.value)}
            placeholder="Enter token ID to claim"
            disabled={claiming}
            fieldSize="md"
          />
        </Box>

        {result?.success ? (
          <Box gap="md" style={{ marginTop: "16px" }}>
            <Text as="p" size="lg" style={{ color: "#4caf50" }}>
              ✓ Claim Successful!
            </Text>
            <Text as="p" size="sm" style={{ color: "#666" }}>
              Token {result.tokenId} has been successfully claimed to your wallet.
            </Text>
            <Button
              type="button"
              variant="secondary"
              size="md"
              onClick={() => {
                setResult(undefined);
                setTokenId("");
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
              {typeof result.error === 'string' ? result.error : String(result.error || 'Unknown error')}
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
              disabled={claiming || !isReady || !tokenId.trim()}
              isLoading={claiming}
              variant="primary"
              size="md"
            >
              Claim NFT with Chip
            </Button>

            {claiming && claimStep !== 'idle' && (
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
