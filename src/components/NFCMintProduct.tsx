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
import { bytesToHex, hexToBytes, createSEP53Message, determineRecoveryId } from "../util/crypto";
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
  const [result, setResult] = useState<{
    success: boolean;
    tokenId?: string;
    publicKey?: string;
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

      // 1. Read chip's public key (this will be the token ID)
      setMintStep('reading');
      const chipPublicKey = await readChip(keyId);
      
      // 2. Get network-specific settings
      const networkPassphraseToUse = getNetworkPassphrase(walletNetwork, walletPassphrase);
      
      // 3. Use nonce 0 (start of counter for this chip)
      const nonce = 0;
      
      // 4. Get contract client for the wallet's network (with correct RPC, Horizon, and passphrase)
      // getContractId always returns a string (throws if not configured)
      const contractIdValue = getContractId(walletNetwork);
      if (!contractIdValue) {
        throw new Error('Contract ID is required but was not configured');
      }
      const contractId: string = contractIdValue;
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
      const { signatureBytes, recoveryId: providedRecoveryId } = signatureResult;

      // 6. Determine recovery ID and recover token_id (chip's public key)
      // Use provided recovery ID if valid, otherwise determine it
      setMintStep('recovering');
      let recoveryId: number;
      
      // Use provided recovery ID if it's valid (0-3)
      if (providedRecoveryId !== undefined && Number.isInteger(providedRecoveryId) && providedRecoveryId >= 0 && providedRecoveryId <= 3) {
        recoveryId = providedRecoveryId;
      } else {
        // Determine recovery ID by trying all possibilities
        recoveryId = await determineRecoveryId(messageHash, signatureBytes, chipPublicKey);
      }
      
      // Ensure recoveryId is a valid integer between 0 and 3
      if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
        throw new Error(`Invalid recovery ID: ${recoveryId}. Must be an integer between 0 and 3.`);
      }
      
      // Recover public key from signature for verification (not for token_id)
      // @noble/secp256k1 recoverPublicKey always expects 'recovered' format:
      // signature must be 65 bytes = [recovery_id (1 byte)] || [r (32 bytes)] || [s (32 bytes)]
      // messageHash is already hashed, so we set prehash: false
      // recoverPublicKey returns compressed (33 bytes), but we need uncompressed (65 bytes) for comparison
      const secp256k1 = await import('@noble/secp256k1');
      // Construct 65-byte signature with recovery ID as FIRST byte, then r and s
      const recoveredSignature = new Uint8Array(65);
      recoveredSignature[0] = recoveryId; // Recovery ID is first byte
      recoveredSignature.set(signatureBytes, 1); // r (32 bytes) + s (32 bytes) follow
      const compressedKey = secp256k1.recoverPublicKey(
        recoveredSignature,
        messageHash,
        { prehash: false }
      );
      // Convert compressed (33 bytes) to uncompressed (65 bytes) format
      const point = secp256k1.Point.fromBytes(compressedKey);
      const recoveredKeyBytes = point.toBytes(false); // false = uncompressed
      
      // Convert chip's public key (hex string) to bytes for token_id
      // token_id MUST be the public key read from the chip, not the recovered key
      const chipPublicKeyBytes = hexToBytes(chipPublicKey);
      
      // Verify recovered key matches chip's public key
      const recoveredKeyHex = bytesToHex(recoveredKeyBytes);
      if (recoveredKeyHex.toLowerCase() !== chipPublicKey.toLowerCase()) {
        throw new Error(`Signature verification failed: Recovered key does not match chip public key. Recovered: ${recoveredKeyHex.substring(0, 20)}...${recoveredKeyHex.substring(recoveredKeyHex.length - 20)}, Chip: ${chipPublicKey.substring(0, 20)}...${chipPublicKey.substring(chipPublicKey.length - 20)}`);
      }
      
      // 7. Build and submit transaction using contract client with wallet kit
      setMintStep('calling');
      
      // Build transaction using contract client with wallet's public key
      // The contract client needs the publicKey to build the transaction with the correct source account
      // IMPORTANT: message must be WITHOUT nonce - contract appends nonce internally
      // Contract uses provided recovery_id to recover and verifies it matches token_id
      // token_id MUST be the public key read from the chip (not the recovered key)
      const tx = await contractClient.mint(
        {
          to: address,
          message: Buffer.from(message), // Message WITHOUT nonce
          signature: Buffer.from(signatureBytes),
          recovery_id: recoveryId, // Recovery ID determined by client
          token_id: Buffer.from(chipPublicKeyBytes), // Chip's public key read from chip (65 bytes, uncompressed)
          nonce: nonce, // Nonce passed separately
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
      // The contract's mint function returns the token_id (chip's public key)
      const returnedTokenId = txResponse.result;
      const returnedTokenIdHex = bytesToHex(new Uint8Array(returnedTokenId));
      const passedTokenIdHex = bytesToHex(chipPublicKeyBytes);
      const tokenIdHex = returnedTokenIdHex; // For compatibility with existing code
      
      // Validate that returned token_id matches what we passed (chip's public key)
      // Contract verifies signature recovers to token_id internally
      if (returnedTokenIdHex.toLowerCase() !== passedTokenIdHex.toLowerCase()) {
        const errorMsg = `Token ID mismatch! Passed: ${passedTokenIdHex.substring(0, 20)}...${passedTokenIdHex.substring(passedTokenIdHex.length - 20)}, Returned: ${returnedTokenIdHex.substring(0, 20)}...${returnedTokenIdHex.substring(returnedTokenIdHex.length - 20)}`;
        throw new Error(`Contract returned different token_id: ${errorMsg}`);
      }
      
      // Validate that returned token_id matches chip's public key (should always match since we passed it)
      if (returnedTokenIdHex.toLowerCase() !== chipPublicKey.toLowerCase()) {
        console.warn('Token ID does not match chip public key. This may indicate a key mismatch.');
      }
      
      // 8. Write NDEF URL to chip after successful mint
      setMintStep('writing-ndef');
      let ndefWriteSuccess = false;
      try {
        const ndefUrl = `https://nft.stellarmerchshop.com/${tokenIdHex}`;
        await writeNDEF(ndefUrl);
        ndefWriteSuccess = true;
      } catch (ndefError) {
        console.error('Failed to write NDEF (mint still successful):', ndefError);
        // Don't fail the mint if NDEF write fails
      }
      
      setResult({
        success: true,
        tokenId: tokenIdHex,
        publicKey: tokenIdHex,
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
          Select the key ID to use for all operations (1-255). This key ID will be used for minting, fetching key information, and generating signatures.
        </Text>
        <Box gap="sm" direction="row" style={{ alignItems: "flex-end" }}>
          <Box gap="xs" direction="column" style={{ flex: 1, maxWidth: "200px" }}>
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
              ✓ NDEF URL written to chip: https://nft.stellarmerchshop.com/{result.publicKey}
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

