/**
 * useErrorHandler Hook
 * Provides consistent error handling with notifications
 */

import { useCallback } from "react";
import { useNotification } from "./useNotification.ts";
import { handleChipError, formatChipError } from "../util/chipErrorHandler.ts";

export interface ErrorHandlerOptions {
  showNotification?: boolean;
  logError?: boolean;
  fallbackMessage?: string;
}

export const useErrorHandler = () => {
  const { addNotification } = useNotification();

  const handleError = useCallback(
    (error: unknown, options: ErrorHandlerOptions = {}) => {
      const {
        showNotification = true,
        logError = true,
        fallbackMessage = "An unexpected error occurred",
      } = options;

      if (logError) {
        console.error("Error handled:", error);
      }

      // Try chip-specific error handling first
      try {
        const chipErrorResult = handleChipError(error);
        const errorMessage = formatChipError(chipErrorResult);

        if (showNotification) {
          addNotification(chipErrorResult.errorMessage, "error");
        }

        return {
          message: errorMessage,
          userMessage: chipErrorResult.errorMessage,
          guidance: chipErrorResult.actionableGuidance,
          isChipError: true,
        };
      } catch {
        // Not a chip error, handle generically
        const errorMessage =
          error instanceof Error ? error.message : fallbackMessage;

        if (showNotification) {
          addNotification(errorMessage, "error");
        }

        return {
          message: errorMessage,
          userMessage: errorMessage,
          guidance: "",
          isChipError: false,
        };
      }
    },
    [addNotification],
  );

  const handleAsyncOperation = useCallback(
    async <T>(
      operation: () => Promise<T>,
      options: ErrorHandlerOptions = {},
    ): Promise<T | null> => {
      try {
        return await operation();
      } catch (error) {
        handleError(error, options);
        return null;
      }
    },
    [handleError],
  );

  return {
    handleError,
    handleAsyncOperation,
  };
};
