/**
 * useContractId Hook
 * Manages contract ID state and syncs with network defaults
 */

import { useState, useEffect } from "react";
import { getContractId } from "../contracts/util.ts";

export const useContractId = (walletNetwork?: string) => {
  const [contractId, setContractId] = useState<string>("");

  // Sync contract ID with network default when network changes
  useEffect(() => {
    if (walletNetwork) {
      try {
        const defaultContractId = getContractId(walletNetwork);
        setContractId(defaultContractId);
      } catch (error) {
        // If contract ID is not configured for this network, leave it empty
        // User can manually enter it
        setContractId("");
      }
    }
  }, [walletNetwork]);

  return { contractId, setContractId };
};
