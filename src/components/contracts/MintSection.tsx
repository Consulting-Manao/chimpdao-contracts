/**
 * Mint Section Component
 * Handles NFT minting with NFC chip authentication
 */

import { useState } from "react";
import { Button, Text, Code } from "@stellar/design-system";
import { Box } from "../layout/Box";
import { ChipProgressIndicator } from "../ChipProgressIndicator";
import { useWallet } from "../../hooks/useWallet";
import { useNFC } from "../../hooks/useNFC";
import { useChipAuth } from "../../hooks/useChipAuth";
import { useContractClient } from "../../hooks/useContractClient";
import { createSEP53Message } from "../../util/crypto";
import { getNetworkPassphrase } from "../../contracts/util";
import { NFCServerNotRunningError, ChipNotPresentError, APDUCommandFailedError, RecoveryIdError } from "../../util/nfcClient";

type MintStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming' | 'writing-ndef';

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

export const MintSection = ({ keyId, contractId }: MintSectionProps) => {
  const { address, updateBalances, signTransaction, network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();
  const { connected, connect, writeNDEF } = useNFC();
  const { authenticateWithChip } = useChipAuth();
  const { contractClient, isReady } = useContractClient(contractId);
  const [minting, setMinting] = useState(false);
  const [mintStep, setMintStep] = useState<MintStep>('idle');
  const [result, setResult] = useState<MintResult>();

  const steps: MintStep[] = ['reading', 'signing', 'recovering', 'calling', 'confirming', 'writing-ndef'];

  const getStepMessage = (step: MintStep): string => {
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
      case 'writing-ndef':
        return 'Writing NDEF URL to chip...';
      default:
        return 'Processing...';
    }
  };

  const handleMint = async () => {
    if (!address) return;
    if (!isReady || !contractClient) {
      throw new Error('Contract client is not ready. Please check your contract ID.');
    }

    setMinting(true);
    setMintStep('idle');
    setResult(undefined);

    try {
      // Ensure we're connected to NFC server
      if (!connected) {
        setMintStep('reading');
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

      // Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(walletNetwork, walletPassphrase);
      const nonce = 0; // Start of counter for this chip

      // Create SEP-53 message
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'mint',
        [address],
        nonce,
        networkPassphraseToUse
      );

      // Authenticate with chip
      setMintStep('reading');
      const authResult = await authenticateWithChip(keyIdNum, messageHash);

      // Call contract
      setMintStep('calling');
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
        } as any
      );

      // Sign and send transaction
      setMintStep('confirming');
      const txResponse = await tx.signAndSend({ signTransaction, force: true });

      // Contract returns u64 token_id (bigint)
      const returnedTokenId = txResponse.result as bigint;
      const tokenIdString = returnedTokenId.toString();

      // Write NDEF URL to chip after successful mint
      setMintStep('writing-ndef');
      let ndefWriteSuccess = false;
      try {
        const ndefUrl = `https://nft.stellarmerchshop.com/${contractId}/${tokenIdString}`;
        await writeNDEF(ndefUrl);
        ndefWriteSuccess = true;
      } catch (ndefError) {
        console.error('Failed to write NDEF (mint still successful):', ndefError);
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
      console.error('Minting error:', err);

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
      setMinting(false);
      setMintStep('idle');
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
          <Text as="p" size="sm" weight="semi-bold" style={{ marginTop: "12px" }}>
            Chip Public Key (Token ID):
          </Text>
          <Code size="sm" style={{ wordBreak: "break-all", display: "block", padding: "8px", backgroundColor: "#f5f5f5" }}>
            {result.publicKey}
          </Code>
          <Text as="p" size="xs" style={{ marginTop: "8px", color: "#666" }}>
            This 65-byte public key is the NFT token ID. The NFT has been successfully minted to your wallet.
          </Text>
          {result.ndefWriteSuccess && (
            <Text as="p" size="xs" style={{ marginTop: "8px", color: "#4caf50" }}>
              ✓ NDEF URL written to chip: https://nft.stellarmerchshop.com/{result.contractId}/{result.tokenId}
            </Text>
          )}
          {result.ndefWriteSuccess === false && (
            <Text as="p" size="xs" style={{ marginTop: "8px", color: "#ff9800" }}>
              ⚠️ Mint successful, but NDEF URL could not be written to chip (chip may be locked or read-only)
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

          {minting && mintStep !== 'idle' && (
            <ChipProgressIndicator
              step={mintStep}
              stepMessage={getStepMessage(mintStep)}
              steps={steps}
            />
          )}
        </Box>
      )}
    </form>
  );
};
