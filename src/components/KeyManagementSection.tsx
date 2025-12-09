/**
 * Reusable section component for key management operations
 * Handles generating new keys and fetching keys by ID
 */

import { useState } from "react";
import { Button, Text } from "@stellar/design-system";
import { Box } from "./layout/Box";
import { useNFC } from "../hooks/useNFC";
import { KeyInfoDisplay } from "./KeyInfoDisplay";
import { ChipNotPresentError } from "../util/nfcClient";
import type { KeyInfo } from "../util/nfcClient";

interface KeyManagementSectionProps {
  keyId: number;
  onKeyFetched?: (keyInfo: KeyInfo) => void;
  onKeyGenerated?: (keyInfo: KeyInfo) => void;
}

export const KeyManagementSection = ({ keyId, onKeyFetched, onKeyGenerated }: KeyManagementSectionProps) => {
  const { connected, generatingKey, fetchingKey, generateKey, fetchKeyById, connect } = useNFC();
  const [fetchedKey, setFetchedKey] = useState<KeyInfo | null>(null);
  const [generatedKey, setGeneratedKey] = useState<KeyInfo | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleFetchKey = async () => {
    if (!connected) {
      try {
        await connect();
      } catch (err) {
        setError(`Failed to connect: ${err instanceof Error ? err.message : 'Unknown error'}`);
        return;
      }
    }

    if (isNaN(keyId) || keyId < 1 || keyId > 255) {
      setError('Key ID must be between 1 and 255');
      return;
    }

    setError(null);
    try {
      const keyInfo = await fetchKeyById(keyId);
      setFetchedKey(keyInfo);
      onKeyFetched?.(keyInfo);
    } catch (err) {
      if (err instanceof ChipNotPresentError) {
        setError('No NFC chip detected. Please place the chip on the reader.');
      } else {
        const errorMessage = err instanceof Error ? err.message : 'Unknown error';
        // Check if it's a "key not found" error
        if (errorMessage.includes('does not exist') || errorMessage.includes('Key not found')) {
          setError(`Key ID ${keyId} does not exist on this chip. Generate a key first or try a different key ID.`);
        } else {
          setError(`Failed to fetch key: ${errorMessage}`);
        }
      }
    }
  };

  const handleGenerateKey = async () => {
    if (!connected) {
      try {
        await connect();
      } catch (err) {
        setError(`Failed to connect: ${err instanceof Error ? err.message : 'Unknown error'}`);
        return;
      }
    }

    setError(null);
    try {
      const keyInfo = await generateKey();
      setGeneratedKey(keyInfo);
      onKeyGenerated?.(keyInfo);
    } catch (err) {
      if (err instanceof ChipNotPresentError) {
        setError('No NFC chip detected. Please place the chip on the reader.');
      } else {
        setError(`Failed to generate key: ${err instanceof Error ? err.message : 'Unknown error'}`);
      }
    }
  };

  return (
    <Box gap="md" direction="column" style={{ marginBottom: "32px" }}>

      <Text as="p" size="sm" style={{ color: "#666", marginBottom: "24px" }}>
        Generate new keys or fetch existing keys from the NFC chip. Chips come empty and need a key to be generated first.
      </Text>

      {error && (
        <Box style={{ 
          padding: "12px", 
          backgroundColor: "#fee", 
          borderRadius: "4px",
          border: "1px solid #fcc",
          marginBottom: "16px"
        }}>
          <Text as="p" size="sm" style={{ color: "#c00" }}>
            {error}
          </Text>
        </Box>
      )}

      {/* Fetch Key Section */}
      <Box gap="sm" direction="column" style={{ 
        marginBottom: "24px", 
        border: "1px solid #eee", 
        borderRadius: "8px", 
        padding: "20px", 
        backgroundColor: "#fafafa" 
      }}>
        <Text as="h3" size="md" weight="semi-bold" style={{ marginBottom: "12px" }}>
          Fetch Key
        </Text>
        <Text as="p" size="sm" style={{ color: "#666", marginBottom: "16px" }}>
          Fetch key information for Key ID {keyId} from the chip.
        </Text>
        <Button
          type="button"
          variant="primary"
          size="md"
          onClick={handleFetchKey}
          disabled={fetchingKey}
          isLoading={fetchingKey}
        >
          {fetchingKey ? "Fetching..." : "Fetch Key"}
        </Button>
        
        {fetchedKey && (
          <Box style={{ marginTop: "16px" }}>
            <KeyInfoDisplay keyInfo={fetchedKey} label="Fetched Key Information" />
          </Box>
        )}
      </Box>

      {/* Generate Key Section */}
      <Box gap="sm" direction="column" style={{ 
        border: "1px solid #eee", 
        borderRadius: "8px", 
        padding: "20px", 
        backgroundColor: "#fafafa" 
      }}>
        <Text as="h3" size="md" weight="semi-bold" style={{ marginBottom: "12px" }}>
          Generate New Key
        </Text>
        <Text as="p" size="sm" style={{ color: "#666", marginBottom: "16px" }}>
          Generate a new keypair on the chip. The chip will return the new key ID and public key.
        </Text>
        
        <Button
          type="button"
          variant="primary"
          size="md"
          onClick={handleGenerateKey}
          disabled={generatingKey}
          isLoading={generatingKey}
        >
          {generatingKey ? "Generating..." : "Generate New Key"}
        </Button>
        
        {generatedKey && (
          <Box style={{ marginTop: "16px" }}>
            <KeyInfoDisplay keyInfo={generatedKey} label="Generated Key Information" />
          </Box>
        )}
      </Box>
    </Box>
  );
};

