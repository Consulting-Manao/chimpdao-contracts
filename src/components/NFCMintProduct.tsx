/**
 * NFC Mint Product Component
 * Allows minting NFTs using NFC chip signatures
 * Replaces the GuessTheNumber component
 */

import { useState, useEffect } from "react";
import { Button, Text, Code } from "@stellar/design-system";
import { useWallet } from "../hooks/useWallet";
import { useNFC } from "../hooks/useNFC";
import { Box } from "./layout/Box";
import { bytesToHex, createSEP53Message, fetchCurrentLedger, determineRecoveryId } from "../util/crypto";
import { getNetworkPassphrase, getHorizonUrl } from "../contracts/util";
import { getContractClient } from "../contracts/stellar_merch_shop";
import { NFCServerNotRunningError, ChipNotPresentError, APDUCommandFailedError, RecoveryIdError } from "../util/nfcClient";

type MintStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming' | 'writing-ndef';

export const NFCMintProduct = () => {
  const { address, updateBalances, signTransaction, network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();
  const { connected, signing, signWithChip, readChip, connect, readNDEF, writeNDEF, readingNDEF } = useNFC();
  const [minting, setMinting] = useState(false);
  const [mintStep, setMintStep] = useState<MintStep>('idle');
  const [ndefData, setNdefData] = useState<string | null>(null);
  const [result, setResult] = useState<{
    success: boolean;
    tokenId?: string;
    publicKey?: string;
    error?: string;
  }>();

  // Auto-connect to NFC server on component mount
  useEffect(() => {
    if (!connected) {
      console.log('NFCMintProduct: Auto-connecting to NFC server...');
      connect().catch((err) => {
        console.warn('NFCMintProduct: Auto-connect failed (server may not be running):', err);
        // Don't show error - server might not be running yet
      });
    }
  }, [connected, connect]);

  if (!address) {
    return (
      <Text as="p" size="md">
        Connect wallet to mint NFTs with NFC chip
      </Text>
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
      case 'writing-ndef':
        return 'Writing NDEF URL to chip...';
      default:
        return 'Processing...';
    }
  };

  const handleReadNDEF = async () => {
    console.log('handleReadNDEF: Starting...');
    if (!connected) {
      console.log('handleReadNDEF: Not connected, connecting...');
      await connect();
    }

    try {
      console.log('handleReadNDEF: Calling readNDEF()...');
      const url = await readNDEF();
      console.log('handleReadNDEF: Got URL:', url);
      setNdefData(url);
      console.log('handleReadNDEF: Set ndefData to:', url);
    } catch (err) {
      console.error('handleReadNDEF: Error:', err);
      if (err instanceof ChipNotPresentError) {
        setNdefData(null);
        alert('No NFC chip detected. Please place the chip on the reader.');
      } else {
        console.error('Failed to read NDEF:', err);
        alert(`Failed to read NDEF: ${err instanceof Error ? err.message : 'Unknown error'}`);
      }
    }
  };

  const handleMint = async () => {
    if (!address) return;

    setMinting(true);
    setMintStep('idle');
    setResult(undefined);

    try {
      // 0. Ensure we're connected to NFC server
      if (!connected) {
        setMintStep('reading');
        await connect();
      }
      
      // 1. Read chip's public key (this will be the token ID)
      setMintStep('reading');
      const chipPublicKey = await readChip();
      
      // 2. Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(walletNetwork, walletPassphrase);
      const horizonUrlToUse = getHorizonUrl(walletNetwork);
      
      // 3. Fetch current ledger using wallet's network Horizon URL
      let currentLedger: number;
      try {
        currentLedger = await fetchCurrentLedger(horizonUrlToUse);
      } catch {
        // Fallback to reasonable default if Horizon API fails
        currentLedger = 1000000;
      }
      const validUntilLedger = currentLedger + 100;
      
      // 4. Get contract client for the wallet's network (with correct RPC, Horizon, and passphrase)
      const contractClient = getContractClient(walletNetwork, walletPassphrase);
      const contractId = contractClient.options.contractId;
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'mint',
        [address],
        validUntilLedger,
        networkPassphraseToUse
      );

      // 5. NFC chip signs the hash
      setMintStep('signing');
      const signatureResult = await signWithChip(messageHash);
      const { signatureBytes, recoveryId: providedRecoveryId } = signatureResult;

      // 6. Determine recovery ID
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
      
      // 7. Build and submit transaction using contract client with wallet kit
      setMintStep('calling');
      
      // Debug logging
      console.log('Minting with:', {
        to: address,
        messageLength: message.length,
        signatureLength: signatureBytes.length,
        recoveryId,
        contractId: contractId,
        publicKey: address
      });
      
      // Build transaction using contract client with wallet's public key
      // The contract client needs the publicKey to build the transaction with the correct source account
      const tx = await contractClient.mint(
        {
          to: address,
          message: Buffer.from(message),
          signature: Buffer.from(signatureBytes),
          recovery_id: recoveryId,
        },
        {
          publicKey: address, // Required: use the connected wallet's public key
        } as any // Type assertion needed because AssembledTransactionOptions requires full ClientOptions
      );
      
      // Sign and send using wallet kit
      // Use force: true because this will be a write operation in the future
      setMintStep('confirming');
      const txResponse = await tx.signAndSend({ signTransaction, force: true });
      
      // Get result from the transaction response
      // The contract's mint function returns the recovered public key (token ID)
      const recoveredPublicKey = txResponse.result;
      const tokenIdHex = bytesToHex(new Uint8Array(recoveredPublicKey));
      
      console.log('Mint successful! Token ID:', tokenIdHex);
      
      // 8. Write NDEF URL to chip after successful mint
      setMintStep('writing-ndef');
      try {
        const ndefUrl = `https://nft.stellarmerchshop.com/${tokenIdHex}`;
        await writeNDEF(ndefUrl);
        console.log('NDEF URL written successfully:', ndefUrl);
      } catch (ndefError) {
        console.error('Failed to write NDEF (mint still successful):', ndefError);
        // Don't fail the mint if NDEF write fails
      }
      
      setResult({
        success: true,
        tokenId: tokenIdHex,
        publicKey: tokenIdHex,
      });
      
      await updateBalances();
    } catch (err) {
      // Enhanced error logging
      console.error('Minting error:', err);
      if (err instanceof Error) {
        console.error('Error message:', err.message);
        console.error('Error stack:', err.stack);
      }
      
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
      {/* NDEF Read Section */}
      <Box gap="sm" direction="column" style={{ marginBottom: "24px", padding: "16px", backgroundColor: "#f9f9f9", borderRadius: "8px", border: "1px solid #e0e0e0" }}>
        <Text as="p" size="md" weight="semi-bold" style={{ marginBottom: "8px" }}>
          NDEF Data
        </Text>
        <Button
          type="button"
          variant="secondary"
          size="md"
          onClick={handleReadNDEF}
          disabled={readingNDEF}
          isLoading={readingNDEF}
        >
          {readingNDEF ? "Reading NDEF..." : "Read NDEF Data"}
        </Button>
        
        {ndefData !== null && (
          <Box gap="xs" direction="column" style={{ marginTop: "12px", padding: "12px", backgroundColor: "#fff", borderRadius: "4px", border: "1px solid #ddd" }}>
            <Text as="p" size="sm" weight="semi-bold" style={{ color: "#333" }}>
              {ndefData ? "NDEF URL:" : "Status:"}
            </Text>
            {ndefData ? (
              <Box gap="xs" direction="column">
                <Code size="sm" style={{ wordBreak: "break-all", display: "block", padding: "8px", backgroundColor: "#f5f5f5", borderRadius: "4px" }}>
                  {ndefData}
                </Code>
                <Box as="a" href={ndefData} target="_blank" rel="noopener noreferrer" style={{ marginTop: "8px" }}>
                  <Button type="button" variant="tertiary" size="sm">
                    Open URL
                  </Button>
                </Box>
              </Box>
            ) : (
              <Text as="p" size="sm" style={{ color: "#666", fontStyle: "italic" }}>
                No NDEF data found on chip
              </Text>
            )}
          </Box>
        )}
      </Box>

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
          <Text as="p" size="xs" style={{ marginTop: "8px", color: "#4caf50" }}>
            ✓ NDEF URL written to chip: https://nft.stellarmerchshop.com/{result.publicKey}
          </Text>
          <Button
            type="button"
            variant="secondary"
            size="md"
            onClick={() => {
              setResult(undefined);
              setNdefData(null);
            }}
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

          <Button
            type="submit"
            disabled={minting || signing}
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
                  backgroundColor: ['recovering', 'calling', 'confirming', 'writing-ndef'].includes(mintStep) ? "#4caf50" : "#ddd"
                }} />
              </Box>
            </Box>
          )}
        </Box>
      )}
    </form>
  );
};

