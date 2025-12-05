/**
 * NFC Mint Product Component
 * Allows minting NFTs using NFC chip signatures
 * Replaces the GuessTheNumber component
 */

import { useState } from "react";
import { Button, Text, Code } from "@stellar/design-system";
import { useWallet } from "../hooks/useWallet";
import { useNFC } from "../hooks/useNFC";
import { Box } from "./layout/Box";
import { bytesToHex, createSEP53Message, fetchCurrentLedger, determineRecoveryId } from "../util/crypto";
import { networkPassphrase, horizonUrl } from "../contracts/util";
import stellarMerchShop from "../contracts/stellar_merch_shop";
import { NFCServerNotRunningError, ChipNotPresentError, APDUCommandFailedError, RecoveryIdError } from "../util/nfcClient";

type MintStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming';

export const NFCMintProduct = () => {
  const { address, updateBalances, signTransaction } = useWallet();
  const { connected, chipPresent, signing, signWithChip, mode, modeName, readChip } = useNFC();
  const [minting, setMinting] = useState(false);
  const [mintStep, setMintStep] = useState<MintStep>('idle');
  const [result, setResult] = useState<{
    success: boolean;
    tokenId?: string;
    publicKey?: string;
    error?: string;
  }>();

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to mint NFTs with NFC chip
      </Text>
    );
  }

  if (!connected && mode === 'websocket') {
    return (
      <Box gap="sm">
        <Text as="p" size="md">
          NFC server not running (Desktop mode)
        </Text>
        <Text as="p" size="sm" style={{ color: "#666" }}>
          Start the NFC server in a separate terminal:
        </Text>
        <Code size="md">bun run nfc-server</Code>
        <Text as="p" size="sm" style={{ color: "#666", marginTop: "8px" }}>
          Or start everything together:
        </Text>
        <Code size="md">bun run dev:with-nfc</Code>
      </Box>
    );
  }

  if (mode === 'none') {
    return (
      <Box gap="sm">
        <Text as="p" size="md">
          NFC not available on this device
        </Text>
        <Text as="p" size="sm" style={{ color: "#666" }}>
          {/iPhone|iPad|iPod/.test(navigator.userAgent) ? (
            <>
              Please install and start the iOS Bridge app to use this feature.
            </>
          ) : (
            <>
              Please connect a USB NFC reader and start the NFC server to use this feature.
            </>
          )}
        </Text>
      </Box>
    );
  }

  if (!chipPresent && mode === 'websocket') {
    return (
      <Box gap="sm">
        <Text as="p" size="md">
          Place NFC chip on reader
        </Text>
        <Text as="p" size="sm" style={{ color: "#666" }}>
          Position your Infineon NFC chip on the uTrust 4701F reader to continue
        </Text>
      </Box>
    );
  }

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
      default:
        return 'Processing...';
    }
  };

  const handleMint = async () => {
    if (!address) return;

    setMinting(true);
    setMintStep('idle');
    setResult(undefined);

    try {
      // 1. Read chip's public key (this will be the token ID)
      setMintStep('reading');
      const chipPublicKey = await readChip();
      
      // 2. Get current ledger for SEP-53 expiry
      let currentLedger: number;
      try {
        currentLedger = await fetchCurrentLedger(horizonUrl);
      } catch {
        // Fallback to reasonable default if Horizon API fails
        currentLedger = 1000000;
      }
      const validUntilLedger = currentLedger + 100;
      
      // 3. Create SEP-53 compliant auth message
      const contractId = stellarMerchShop.options.contractId;
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'mint',
        [address],
        validUntilLedger,
        networkPassphrase
      );

      // 4. NFC chip signs the hash
      setMintStep('signing');
      const signatureResult = await signWithChip(messageHash);
      const { signatureBytes, recoveryId: providedRecoveryId } = signatureResult;

      // 5. Determine recovery ID
      // If server provided recovery ID and it's valid, use it; otherwise try all possibilities
      setMintStep('recovering');
      let recoveryId: number;
      if (providedRecoveryId !== undefined && providedRecoveryId >= 0 && providedRecoveryId <= 3) {
        // Validate that this recovery ID produces the correct public key
        try {
          const validationId = await determineRecoveryId(messageHash, signatureBytes, chipPublicKey);
          if (validationId === providedRecoveryId) {
            recoveryId = providedRecoveryId; // Server provided correct recovery ID
          } else {
            // Server recovery ID doesn't match, use validated one
            recoveryId = validationId;
          }
        } catch {
          // If validation fails, trust server's recovery ID
          recoveryId = providedRecoveryId;
        }
      } else {
        // Server didn't provide recovery ID, determine it
        recoveryId = await determineRecoveryId(messageHash, signatureBytes, chipPublicKey);
      }
      
      // 6. Call contract with ORIGINAL message
      setMintStep('calling');
      const tx = await stellarMerchShop.mint(
        {
          to: address,
          message: Buffer.from(message),
          signature: Buffer.from(signatureBytes),
          recovery_id: recoveryId,
        }
      );
      
      setMintStep('confirming');
      const txResponse = await tx.signAndSend({ signTransaction });
      
      const recoveredPublicKey = txResponse.result;
      const tokenIdHex = bytesToHex(new Uint8Array(recoveredPublicKey));
      
      setResult({
        success: true,
        tokenId: tokenIdHex,
        publicKey: tokenIdHex,
      });
      
      await updateBalances();
    } catch (err) {
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
        errorMessage = err.message;
        // Provide guidance based on error message content
        if (err.message.includes("timeout") || err.message.includes("Timeout")) {
          actionableGuidance = "The operation took too long. Please ensure the chip is positioned correctly and try again.";
        } else if (err.message.includes("connection") || err.message.includes("WebSocket")) {
          actionableGuidance = "Check that the NFC server is running: bun run nfc-server";
        }
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
            This 65-byte public key would become the NFT token ID when the contract is called.
            Currently showing test flow - contract call will be enabled once scaffold generates the client.
          </Text>
          <Button
            type="button"
            variant="secondary"
            size="md"
            onClick={() => setResult(undefined)}
            style={{ marginTop: "12px" }}
          >
            Test Again
          </Button>
        </Box>
      ) : result?.error ? (
        <Box gap="md">
          <Text as="p" size="lg" style={{ color: "#d32f2f" }}>
            ✗ Minting Failed
          </Text>
          <Text as="p" size="sm" style={{ color: "#666" }}>
            {result.error}
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
          <Text as="p" size="md" weight="semi-bold">
            Mint NFT from NFC Chip
          </Text>
          <Text as="p" size="sm" style={{ color: "#666" }}>
            This will create an NFT linked to your physical product. The chip's public key becomes the unique token ID.
          </Text>
          <Text as="p" size="sm" style={{ color: "#666", marginTop: "8px" }}>
            Using {modeName} • SEP-53 Auth
          </Text>

          <Button
            type="submit"
            disabled={(mode === 'websocket' && !chipPresent) || minting || signing}
            isLoading={minting || signing}
            style={{ marginTop: "12px" }}
            variant="primary"
            size="md"
          >
            Mint NFT with Chip
          </Button>

          {(minting || signing) && mintStep !== 'idle' && (
            <Box gap="xs" style={{ marginTop: "12px", padding: "12px", backgroundColor: "#f5f5f5", borderRadius: "4px" }}>
              <Text as="p" size="sm" weight="semi-bold" style={{ color: "#333" }}>
                {getStepMessage(mintStep)}
              </Text>
              <Box gap="xs" direction="row" style={{ marginTop: "4px" }}>
                <div style={{
                  width: "8px",
                  height: "8px",
                  borderRadius: "50%",
                  backgroundColor: mintStep === 'reading' ? "#4caf50" : "#ddd"
                }} />
                <div style={{
                  width: "8px",
                  height: "8px",
                  borderRadius: "50%",
                  backgroundColor: mintStep === 'signing' ? "#4caf50" : (mintStep === 'reading' ? "#ddd" : "#ddd")
                }} />
                <div style={{
                  width: "8px",
                  height: "8px",
                  borderRadius: "50%",
                  backgroundColor: ['recovering', 'calling', 'confirming'].includes(mintStep) ? "#4caf50" : "#ddd"
                }} />
              </Box>
            </Box>
          )}
        </Box>
      )}
    </form>
  );
};

