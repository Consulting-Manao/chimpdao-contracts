/**
 * Generic hook for managing multi-step operations
 * Provides progress tracking and step categorization
 */

import { useState, useCallback } from "react";

export interface StepDefinition {
  message: string;
  category: "chip" | "blockchain" | "other";
}

export interface UseOperationStepsReturn<Step extends string> {
  currentStep: Step | null;
  setStep: (step: Step) => void;
  clearStep: () => void;
  getStepMessage: (step: Step) => string;
  isChipOperation: (step: Step) => boolean;
  isBlockchainOperation: (step: Step) => boolean;
  getProgress: () => { current: number; total: number; percentage: number };
}

/**
 * Hook for managing multi-step operations with progress tracking
 */
export function useOperationSteps<Step extends string>(
  steps: Step[],
  stepDefinitions: Record<Step, StepDefinition>,
): UseOperationStepsReturn<Step> {
  const [currentStep, setCurrentStepState] = useState<Step | null>(null);

  const setStep = useCallback((step: Step) => {
    setCurrentStepState(step);
  }, []);

  const clearStep = useCallback(() => {
    setCurrentStepState(null);
  }, []);

  const getStepMessage = useCallback(
    (step: Step): string => {
      return stepDefinitions[step]?.message || "Processing...";
    },
    [stepDefinitions],
  );

  const isChipOperation = useCallback(
    (step: Step): boolean => {
      return stepDefinitions[step]?.category === "chip";
    },
    [stepDefinitions],
  );

  const isBlockchainOperation = useCallback(
    (step: Step): boolean => {
      return stepDefinitions[step]?.category === "blockchain";
    },
    [stepDefinitions],
  );

  const getProgress = useCallback(() => {
    if (!currentStep) {
      return { current: 0, total: steps.length, percentage: 0 };
    }

    const currentIndex = steps.indexOf(currentStep);
    const current = Math.max(0, currentIndex + 1);
    const percentage = (current / steps.length) * 100;

    return { current, total: steps.length, percentage };
  }, [currentStep, steps]);

  return {
    currentStep,
    setStep,
    clearStep,
    getStepMessage,
    isChipOperation,
    isBlockchainOperation,
    getProgress,
  };
}
