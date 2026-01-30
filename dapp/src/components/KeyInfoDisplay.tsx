/**
 * Reusable component to display key information
 * Shows key ID, public key, and signature counters
 */

import { Text, Code } from "@stellar/design-system";
import { Box } from "./layout/Box.tsx";
import type { KeyInfo } from "../util/nfcClient.ts";

interface KeyInfoDisplayProps {
  keyInfo: KeyInfo;
  label?: string;
}

export const KeyInfoDisplay = ({ keyInfo, label }: KeyInfoDisplayProps) => {
  return (
    <Box
      gap="xs"
      direction="column"
      style={{
        padding: "16px",
        backgroundColor: "#f5f5f5",
        borderRadius: "8px",
        border: "1px solid #e0e0e0",
      }}
    >
      {label && (
        <Text
          as="p"
          size="sm"
          weight="semi-bold"
          style={{ marginBottom: "8px", color: "#666" }}
        >
          {label}
        </Text>
      )}

      <Box gap="xs" direction="column">
        <Box gap="xs" direction="row" style={{ alignItems: "center" }}>
          <Text
            as="p"
            size="sm"
            weight="semi-bold"
            style={{ minWidth: "80px" }}
          >
            Key ID:
          </Text>
          <Text as="p" size="sm">
            {keyInfo.keyId}
          </Text>
        </Box>

        <Box gap="xs" direction="column">
          <Text as="p" size="sm" weight="semi-bold">
            Public Key:
          </Text>
          <Code
            size="sm"
            style={{
              wordBreak: "break-all",
              display: "block",
              padding: "8px",
              backgroundColor: "#fff",
              borderRadius: "4px",
              fontSize: "11px",
              fontFamily: "monospace",
            }}
          >
            {keyInfo.publicKey}
          </Code>
        </Box>

        {(keyInfo.globalCounter !== null || keyInfo.keyCounter !== null) && (
          <Box gap="xs" direction="row" style={{ marginTop: "8px" }}>
            {keyInfo.globalCounter !== null && (
              <Text as="p" size="xs" style={{ color: "#666" }}>
                Global Counter: {keyInfo.globalCounter.toLocaleString()}
              </Text>
            )}
            {keyInfo.keyCounter !== null && (
              <Text
                as="p"
                size="xs"
                style={{ color: "#666", marginLeft: "16px" }}
              >
                Key Counter: {keyInfo.keyCounter.toLocaleString()}
              </Text>
            )}
          </Box>
        )}
      </Box>
    </Box>
  );
};
