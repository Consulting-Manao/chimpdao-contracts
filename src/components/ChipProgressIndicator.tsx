/**
 * Chip Progress Indicator Component
 * Generic progress indicator for chip interactions and contract calls
 */

import { Text } from "@stellar/design-system";
import { Box } from "./layout/Box";

interface ChipProgressIndicatorProps {
  step: string;
  stepMessage: string;
  steps: string[];
}

export const ChipProgressIndicator = ({
  step,
  stepMessage,
  steps,
}: ChipProgressIndicatorProps) => {
  const getStepIndex = () => {
    return steps.indexOf(step);
  };

  const isStepActive = (stepName: string) => {
    const currentIndex = getStepIndex();
    const stepIndex = steps.indexOf(stepName);
    return stepIndex <= currentIndex;
  };

  return (
    <Box gap="xs" style={{ marginTop: "12px", padding: "12px", backgroundColor: "#f5f5f5", borderRadius: "4px" }}>
      <Text as="p" size="sm" weight="semi-bold" style={{ color: "#333" }}>
        {stepMessage}
      </Text>
      <Box gap="xs" direction="row" style={{ marginTop: "4px" }}>
        {steps.map((stepName, index) => (
          <div
            key={stepName}
            style={{
              width: "8px",
              height: "8px",
              borderRadius: "50%",
              backgroundColor: isStepActive(stepName) ? "#4caf50" : "#ddd"
            }}
          />
        ))}
      </Box>
    </Box>
  );
};
