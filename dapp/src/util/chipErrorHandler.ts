/**
 * Shared error handling utility for NFC chip operations
 * Provides consistent error messages and actionable guidance
 */

import {
  NFCServerNotRunningError,
  ChipNotPresentError,
  APDUCommandFailedError,
  RecoveryIdError,
} from "./nfcClient.ts";

export interface ChipErrorResult {
  errorMessage: string;
  actionableGuidance: string;
}

/**
 * Handles errors from NFC chip operations and returns user-friendly messages
 */
export function handleChipError(err: unknown): ChipErrorResult {
  let errorMessage = "Unknown error";
  let actionableGuidance = "";

  if (err instanceof NFCServerNotRunningError) {
    errorMessage = "NFC Server Not Running";
    actionableGuidance =
      "Please start the NFC server in a separate terminal with: bun run nfc-server";
  } else if (err instanceof ChipNotPresentError) {
    errorMessage = "No NFC Chip Detected";
    actionableGuidance =
      "Please place your Infineon NFC chip on the reader and try again.";
  } else if (err instanceof APDUCommandFailedError) {
    errorMessage = "Command Failed";
    actionableGuidance =
      "The chip may not be properly positioned. Try repositioning the chip on the reader.";
  } else if (err instanceof RecoveryIdError) {
    errorMessage = "Recovery ID Detection Failed";
    actionableGuidance =
      "This may indicate a signature mismatch. Please try again.";
  } else if (err instanceof Error) {
    errorMessage = err.message || String(err);
    if (err.message?.includes("timeout") || err.message?.includes("Timeout")) {
      actionableGuidance =
        "The operation took too long. Please ensure the chip is positioned correctly and try again.";
    } else if (
      err.message?.includes("connection") ||
      err.message?.includes("WebSocket")
    ) {
      actionableGuidance =
        "Check that the NFC server is running: bun run nfc-server";
    }
  } else {
    // Handle non-Error objects (e.g., transaction objects)
    errorMessage = String(err) || "Unknown error occurred";
  }

  return {
    errorMessage,
    actionableGuidance,
  };
}

/**
 * Formats error result into a display string
 */
export function formatChipError(result: ChipErrorResult): string {
  return result.actionableGuidance
    ? `${result.errorMessage}\n\n${result.actionableGuidance}`
    : result.errorMessage;
}
