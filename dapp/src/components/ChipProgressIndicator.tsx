/**
 * Chip Progress Indicator Component
 * Generic progress indicator for chip interactions and contract calls
 */

import { Text } from "@stellar/design-system";
import { Box } from "./layout/Box.tsx";

interface ChipProgressIndicatorProps {
  step: string;
  stepMessage: string;
  steps: string[];
  countdown?: number;
}

export const ChipProgressIndicator = ({
  step,
  stepMessage,
  steps,
  countdown,
}: ChipProgressIndicatorProps) => {
  const getStepIndex = () => {
    return steps.indexOf(step);
  };

  const isStepActive = (stepName: string) => {
    const currentIndex = getStepIndex();
    const stepIndex = steps.indexOf(stepName);
    return stepIndex <= currentIndex;
  };

  const isScanning = step === "scanning";

  return (
    <Box
      gap="xs"
      style={{
        marginTop: "12px",
        padding: "12px",
        backgroundColor: "#f5f5f5",
        borderRadius: "4px",
      }}
    >
      <Box gap="xs" direction="row" style={{ alignItems: "center" }}>
        {isScanning && (
          <div
            style={{
              width: "16px",
              height: "16px",
              border: "2px solid #7c3aed",
              borderTop: "2px solid transparent",
              borderRadius: "50%",
              animation: "spin 1s linear infinite",
              marginRight: "8px",
            }}
          />
        )}
        <Text
          as="p"
          size="sm"
          weight="semi-bold"
          style={{ color: "#333", flex: 1 }}
        >
          {stepMessage}
          {countdown !== undefined && countdown >= 0 && (
            <span
              style={{
                marginLeft: "8px",
                color: "#7c3aed",
                fontWeight: "bold",
              }}
            >
              {countdown}s
            </span>
          )}
        </Text>
      </Box>
      <Box gap="xs" direction="row" style={{ marginTop: "4px" }}>
        {steps.map((stepName, index) => (
          <div
            key={stepName}
            style={{
              width: "8px",
              height: "8px",
              borderRadius: "50%",
              backgroundColor: isStepActive(stepName) ? "#4caf50" : "#ddd",
              transition: "background-color 0.3s ease",
              ...(isScanning &&
                stepName === "scanning" && {
                  animation: "pulse 1s ease-in-out infinite",
                }),
            }}
          />
        ))}
      </Box>
      <style>{`
        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.6; transform: scale(1.2); }
        }
      `}</style>
    </Box>
  );
};
