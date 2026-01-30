/**
 * NDEF Operations Section Component
 * General-purpose component for reading NDEF data from NFC chips
 */

import { Button, Text, Code } from "@stellar/design-system";
import { Box } from "./layout/Box.tsx";

interface NDEFOperationsSectionProps {
  ndefData: string | null;
  onReadNDEF: () => Promise<void>;
  readingNDEF: boolean;
}

export const NDEFOperationsSection = ({
  ndefData,
  onReadNDEF,
  readingNDEF,
}: NDEFOperationsSectionProps) => {
  return (
    <Box
      gap="sm"
      direction="column"
      style={{
        marginBottom: "24px",
        padding: "16px",
        backgroundColor: "#f9f9f9",
        borderRadius: "8px",
        border: "1px solid #e0e0e0",
      }}
    >
      <Text as="p" size="md" weight="semi-bold" style={{ marginBottom: "8px" }}>
        NDEF Data
      </Text>
      <Button
        type="button"
        variant="secondary"
        size="md"
        onClick={onReadNDEF}
        disabled={readingNDEF}
        isLoading={readingNDEF}
      >
        {readingNDEF ? "Reading NDEF..." : "Read NDEF Data"}
      </Button>

      {ndefData !== null && (
        <Box
          gap="xs"
          direction="column"
          style={{
            marginTop: "12px",
            padding: "12px",
            backgroundColor: "#fff",
            borderRadius: "4px",
            border: "1px solid #ddd",
          }}
        >
          <Text as="p" size="sm" weight="semi-bold" style={{ color: "#333" }}>
            {ndefData ? "NDEF URL:" : "Status:"}
          </Text>
          {ndefData ? (
            <Box gap="xs" direction="column">
              <Code
                size="sm"
                style={{
                  wordBreak: "break-all",
                  display: "block",
                  padding: "8px",
                  backgroundColor: "#f5f5f5",
                  borderRadius: "4px",
                }}
              >
                {ndefData}
              </Code>
              <Button
                type="button"
                variant="tertiary"
                size="sm"
                onClick={() => {
                  if (ndefData) {
                    window.open(ndefData, "_blank", "noopener,noreferrer");
                  }
                }}
                style={{ marginTop: "8px" }}
              >
                Open URL
              </Button>
            </Box>
          ) : (
            <Text
              as="p"
              size="sm"
              style={{ color: "#666", fontStyle: "italic" }}
            >
              No NDEF data found on chip
            </Text>
          )}
        </Box>
      )}
    </Box>
  );
};
