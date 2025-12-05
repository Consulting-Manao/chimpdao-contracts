/**
 * NFC Status Component
 * Displays connection status for NFC server and chip presence
 */

import { Text, Badge } from "@stellar/design-system";
import { useNFC } from "../hooks/useNFC";

export const NFCStatus = () => {
  const { connected, chipPresent, readerName, error } = useNFC();

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        gap: "8px",
        padding: "12px",
        border: "1px solid #ddd",
        borderRadius: "8px",
        backgroundColor: "#f9f9f9",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
        <Text as="span" size="sm" weight="semi-bold">
          Status:
        </Text>
        {connected ? (
          <Badge variant="success">Connected</Badge>
        ) : (
          <Badge variant="error">Disconnected</Badge>
        )}
      </div>

      {connected && readerName && (
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <Text as="span" size="sm" weight="semi-bold">
            Reader:
          </Text>
          <Text as="span" size="sm">
            {readerName}
          </Text>
        </div>
      )}

      {connected && (
        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
          <Text as="span" size="sm" weight="semi-bold">
            Chip:
          </Text>
          {chipPresent ? (
            <Badge variant="success">Detected</Badge>
          ) : (
            <Badge variant="warning">Not Present</Badge>
          )}
        </div>
      )}

      {!connected && (
        <Text as="p" size="sm" style={{ marginTop: "4px", color: "#666" }}>
          Start NFC server with <code>bun run nfc-server</code>
        </Text>
      )}

      {error && (
        <Text as="p" size="sm" style={{ marginTop: "4px", color: "#d32f2f" }}>
          Error: {error}
        </Text>
      )}
    </div>
  );
};

