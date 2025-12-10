/**
 * NFC Mint Product Component
 * Allows minting NFTs using NFC chip signatures
 * Replaces the GuessTheNumber component
 */

import { useState, useEffect } from "react";
import { Button, Text, Code, Input } from "@stellar/design-system";
import { useWallet } from "../hooks/useWallet";
import { useNFC } from "../hooks/useNFC";
import { Box } from "./layout/Box";
import { KeyManagementSection } from "./KeyManagementSection";
import { hexToBytes, createSEP53Message, determineRecoveryId } from "../util/crypto";
import { getNetworkPassphrase, getRpcUrl, getContractId } from "../contracts/util";
import * as Client from "stellar_merch_shop";
import { NFCServerNotRunningError, ChipNotPresentError, APDUCommandFailedError, RecoveryIdError } from "../util/nfcClient";

type MintStep = 'idle' | 'reading' | 'signing' | 'recovering' | 'calling' | 'confirming' | 'writing-ndef';

export const NFCMintProduct = () => {
  const { address, updateBalances, signTransaction, network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();
  const { connected, signing, signWithChip, readChip, connect, readNDEF, writeNDEF, readingNDEF } = useNFC();
  const [minting, setMinting] = useState(false);
  const [mintStep, setMintStep] = useState<MintStep>('idle');
  const [ndefData, setNdefData] = useState<string | null>(null);
  const [selectedKeyId, setSelectedKeyId] = useState<string>("1");
  const [selectedContractId, setSelectedContractId] = useState<string>("");
  const [result, setResult] = useState<{
    success: boolean;
    tokenId?: string;
    publicKey?: string;
    contractId?: string;
    ndefWriteSuccess?: boolean;
    error?: string;
  }>();

  // Auto-connect to NFC server on component mount
  useEffect(() => {
    if (!connected) {
      connect().catch(() => {
        // Server may not be running, user will connect manually
      });
    }
  }, [connected, connect]);

  // Sync contract ID with network default when network changes
  useEffect(() => {
    if (walletNetwork) {
      try {
        const defaultContractId = getContractId(walletNetwork);
        setSelectedContractId(defaultContractId);
      } catch (error) {
        // If contract ID is not configured for this network, leave it empty
        // User can manually enter it
        setSelectedContractId("");
      }
    }
  }, [walletNetwork]);

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
    if (!connected) {
      await connect();
    }

    try {
      const url = await readNDEF();
      setNdefData(url);
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
      
      // Validate keyId before proceeding
      const keyId = parseInt(selectedKeyId, 10);
      if (isNaN(keyId) || keyId < 1 || keyId > 255) {
        throw new Error('Key ID must be between 1 and 255');
      }

      // 1. Read chip's public key
      setMintStep('reading');
      const chipPublicKey = await readChip(keyId);
      
      // 2. Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(walletNetwork, walletPassphrase);
      
      // 3. Use nonce 0 (start of counter for this chip)
      const nonce = 0;
      
      // 4. Get contract client for the wallet's network (with correct RPC, Horizon, and passphrase)
      // Use the selected contract ID from configuration
      if (!selectedContractId || selectedContractId.trim() === '') {
        throw new Error('Contract ID is required. Please enter a contract ID in the Configuration section.');
      }
      const contractId: string = selectedContractId.trim();
      if (!walletPassphrase) {
        throw new Error('Network passphrase is required');
      }
      const networkPassphrase: string = walletPassphrase;
      const contractClient = new Client.Client({
        networkPassphrase,
        contractId,
        rpcUrl: getRpcUrl(walletNetwork),
        allowHttp: true,
        publicKey: undefined,
      });
      const { message, messageHash } = await createSEP53Message(
        contractId,
        'mint',
        [address],
        nonce,
        networkPassphraseToUse
      );

      // 5. NFC chip signs the hash
      setMintStep('signing');
      const signatureResult = await signWithChip(messageHash, keyId);
      const { signatureBytes } = signatureResult;

      // 6. Determine recovery ID by trying all 4 possibilities (0-3)
      // This is quick and ensures we get the correct recovery ID
      setMintStep('recovering');
      const recoveryId = await determineRecoveryId(messageHash, signatureBytes, chipPublicKey);
      
      // Ensure recoveryId is a valid integer between 0 and 3
      if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
        throw new Error(`Invalid recovery ID: ${recoveryId}. Must be an integer between 0 and 3.`);
      }
      
      // Convert chip's public key (hex string) to bytes for passing to contract
      const chipPublicKeyBytes = hexToBytes(chipPublicKey);
      
      // Validate public key format (must be 65 bytes, uncompressed, starting with 0x04)
      if (chipPublicKeyBytes.length !== 65) {
        throw new Error(`Invalid public key length: expected 65 bytes (uncompressed), got ${chipPublicKeyBytes.length} bytes`);
      }
      if (chipPublicKeyBytes[0] !== 0x04) {
        throw new Error(`Invalid public key format: expected uncompressed key (starting with 0x04), got 0x${chipPublicKeyBytes[0].toString(16).padStart(2, '0')}`);
      }
      
      // 7. Build and submit transaction using contract client
      setMintStep('calling');
      
      // Build transaction using contract client
      // Contract will verify signature matches public_key and assign incrementing token_id
      const tx = await contractClient.mint(
        {
          to: address,
          message: Buffer.from(message),
          signature: Buffer.from(signatureBytes),
          recovery_id: recoveryId,
          public_key: Buffer.from(chipPublicKeyBytes), // Chip's public key (65 bytes, uncompressed)
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
        publicKey: chipPublicKey,
        contractId: contractId,
        ndefWriteSuccess,
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
      {/* Configuration Panel */}
      <Box gap="sm" direction="column" style={{ marginBottom: "24px", padding: "16px", backgroundColor: "#f9f9f9", borderRadius: "8px", border: "1px solid #e0e0e0" }}>
        <Text as="p" size="md" weight="semi-bold" style={{ marginBottom: "8px" }}>
          Configuration
        </Text>
        <Text as="p" size="sm" style={{ color: "#666", marginBottom: "12px" }}>
          Configure the key ID and contract address for minting operations. The contract ID defaults to the network's configured value but can be overridden for different collections.
        </Text>
        <Box gap="sm" direction="row" style={{ alignItems: "flex-end", flexWrap: "wrap" }}>
          <Box gap="xs" direction="column" style={{ flex: 1, minWidth: "200px", maxWidth: "250px" }}>
            <Text as="p" size="sm" weight="semi-bold">
              Key ID (1-255)
            </Text>
            <Input
              id="config-key-id-input"
              type="number"
              min="1"
              max="255"
              value={selectedKeyId}
              onChange={(e) => setSelectedKeyId(e.target.value)}
              placeholder="1"
              disabled={minting || signing}
              fieldSize="md"
            />
          </Box>
          <Box gap="xs" direction="column" style={{ flex: 1, minWidth: "300px" }}>
            <Text as="p" size="sm" weight="semi-bold">
              Contract ID
            </Text>
            <Input
              id="config-contract-id-input"
              type="text"
              value={selectedContractId}
              onChange={(e) => setSelectedContractId(e.target.value)}
              placeholder={(() => {
                try {
                  return walletNetwork ? getContractId(walletNetwork) : "Enter contract ID";
                } catch {
                  return "Enter contract ID";
                }
              })()}
              disabled={minting || signing}
              fieldSize="md"
            />
          </Box>
        </Box>
      </Box>

      {/* Key Management Section */}
      <KeyManagementSection keyId={(() => {
        const parsed = parseInt(selectedKeyId, 10);
        return isNaN(parsed) ? 1 : parsed;
      })()} />

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
                <Button
                  type="button"
                  variant="tertiary"
                  size="sm"
                  onClick={() => {
                    if (ndefData) {
                      window.open(ndefData, '_blank', 'noopener,noreferrer');
                    }
                  }}
                  style={{ marginTop: "8px" }}
                >
                  Open URL
                </Button>
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

