/**
 * Transfer Section Component
 * Handles NFT transfer with NFC chip authentication
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

type TransferStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming';

interface TransferSectionProps {
  keyId: string;
  contractId: string;
}

interface TransferResult {
  success: boolean;
  tokenId?: string;
  error?: string;
}

export const TransferSection = ({ keyId, contractId }: TransferSectionProps) => {
  const { address, updateBalances, signTransaction, network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();
  const { connected, connect } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const [transferring, setTransferring] = useState(false);
  const [transferStep, setTransferStep] = useState<TransferStep>('idle');
  const [recipientAddress, setRecipientAddress] = useState("");
  const [tokenId, setTokenId] = useState("");
  const [result, setResult] = useState<TransferResult>();

  const steps: TransferStep[] = ['reading', 'signing', 'recovering', 'calling', 'confirming'];

  const getStepMessage = (step: TransferStep): string => {
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

  const handleTransfer = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error('Contract client is not ready. Please check your contract ID.');
    }

    if (!recipientAddress.trim()) {
      throw new Error('Recipient address is required');
    }

    if (!tokenId.trim()) {
      throw new Error('Token ID is required');
    }

    setTransferring(true);
    setTransferStep('idle');
    setResult(undefined);

    try {
      // Ensure we're connected to NFC server
      if (!connected) {
        setTransferStep('reading');
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

      // Create SEP-53 message for transfer
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'transfer',
        [address, recipientAddress.trim(), tokenIdNum.toString()],
        nonce,
        networkPassphraseToUse
      );

      // Authenticate with chip
      setTransferStep('reading');
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Call contract
      setTransferStep('calling');
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
        } as any
      );

      // Sign and send transaction
      setTransferStep('confirming');
      await tx.signAndSend({ signTransaction, force: true });

      setResult({
        success: true,
        tokenId: tokenId,
      });

      await updateBalances();
    } catch (err) {
      console.error('Transfer error:', err);

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
      setTransferring(false);
      setTransferStep('idle');
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
              disabled={transferring || !isReady || !recipientAddress.trim() || !tokenId.trim()}
              isLoading={transferring}
              variant="primary"
              size="md"
            >
              Transfer NFT with Chip
            </Button>

            {transferring && transferStep !== 'idle' && (
              <ChipProgressIndicator
                step={transferStep}
                stepMessage={getStepMessage(transferStep)}
                steps={steps}
              />
            )}
          </Box>
        )}
      </Box>
    </form>
  );
};
