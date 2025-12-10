/**
 * Configuration Section Component
 * General-purpose configuration for Key ID and Contract ID
 * Used across all contract operations (mint, transfer, balance, etc.)
 */

import { Text, Input } from "@stellar/design-system";
import { Box } from "./layout/Box";
import { getContractId } from "../contracts/util";

interface ConfigurationSectionProps {
  keyId: string;
  contractId: string;
  onKeyIdChange: (keyId: string) => void;
  onContractIdChange: (contractId: string) => void;
  walletNetwork?: string;
  disabled?: boolean;
}

export const ConfigurationSection = ({
  keyId,
  contractId,
  onKeyIdChange,
  onContractIdChange,
  walletNetwork,
  disabled = false,
}: ConfigurationSectionProps) => {
  const getContractIdPlaceholder = () => {
    try {
      return walletNetwork ? getContractId(walletNetwork) : "Enter contract ID";
    } catch {
      return "Enter contract ID";
    }
  };

  return (
    <Box gap="sm" direction="column" style={{ marginBottom: "24px", padding: "16px", backgroundColor: "#f9f9f9", borderRadius: "8px", border: "1px solid #e0e0e0" }}>
      <Text as="p" size="md" weight="semi-bold" style={{ marginBottom: "8px" }}>
        Configuration
      </Text>
      <Text as="p" size="sm" style={{ color: "#666", marginBottom: "12px" }}>
        Configure the key ID and contract address for contract operations. The contract ID defaults to the network's configured value but can be overridden for different collections.
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
            value={keyId}
            onChange={(e) => onKeyIdChange(e.target.value)}
            placeholder="1"
            disabled={disabled}
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
            value={contractId}
            onChange={(e) => onContractIdChange(e.target.value)}
            placeholder={getContractIdPlaceholder()}
            disabled={disabled}
            fieldSize="md"
          />
        </Box>
      </Box>
    </Box>
  );
};
