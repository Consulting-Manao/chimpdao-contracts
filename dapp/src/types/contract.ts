/**
 * Type definitions for contract client calls
 */

import type { MethodOptions } from "@stellar/stellar-sdk/contract";

/**
 * Options for contract method calls that require signing
 * Extends the base MethodOptions with additional signing context
 */
export interface ContractCallOptions extends MethodOptions {
  /**
   * Public key of the signer (used internally by SDK for signing context)
   * This is not part of the official MethodOptions but may be used by the SDK
   */
  publicKey?: string;
}
