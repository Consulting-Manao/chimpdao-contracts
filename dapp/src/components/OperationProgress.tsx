/**
 * Generic operation progress indicator
 * Shows progress for multi-step operations
 */

import { Text } from "@stellar/design-system";
import { Box } from "./layout/Box.tsx";

interface OperationProgressProps {
  step: string;
  stepMessage: string;
  steps: string[];
  type: "chip" | "blockchain";
}

export const OperationProgress = ({
  step,
  stepMessage,
  steps,
  type,
}: OperationProgressProps) => {
  const getStepIndex = () => {
    return steps.indexOf(step);
  };

  const isStepActive = (stepName: string) => {
    const currentIndex = getStepIndex();
    const stepIndex = steps.indexOf(stepName);
    return stepIndex <= currentIndex;
  };

  const colors =
    type === "chip"
      ? { background: "#f5f5f5", active: "#4caf50", text: "#333" }
      : { background: "#e3f2fd", active: "#1976d2", text: "#1976d2" };

  return (
    <Box
      gap="xs"
      style={{
        marginTop: "12px",
        padding: "12px",
        backgroundColor: colors.background,
        borderRadius: "4px",
      }}
    >
      <Text as="p" size="sm" weight="semi-bold" style={{ color: colors.text }}>
        {stepMessage}
      </Text>
      <Box gap="xs" direction="row" style={{ marginTop: "4px" }}>
        {steps.map((stepName) => (
          <div
            key={stepName}
            style={{
              width: "8px",
              height: "8px",
              borderRadius: "50%",
              backgroundColor: isStepActive(stepName) ? colors.active : "#ddd",
              transition: "background-color 0.3s ease",
            }}
          />
        ))}
      </Box>
    </Box>
  );
};
