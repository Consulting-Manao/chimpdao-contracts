/**
 * useContractClient Hook
 * Initialize contract client with proper network settings
 */

import { useMemo } from "react";
import { useWallet } from "./useWallet";
import { getNetworkPassphrase, getRpcUrl } from "../contracts/util";
import * as Client from "stellar_merch_shop";

export const useContractClient = (contractId: string) => {
  const { network: walletNetwork, networkPassphrase: walletPassphrase } = useWallet();

  const contractClient = useMemo(() => {
    if (!contractId || !walletPassphrase || !walletNetwork) {
      return null;
    }

    try {
      const networkPassphrase = getNetworkPassphrase(walletNetwork, walletPassphrase);
      const rpcUrl = getRpcUrl(walletNetwork);

      return new Client.Client({
        networkPassphrase,
        contractId: contractId.trim(),
        rpcUrl,
        allowHttp: true,
        publicKey: undefined,
      });
    } catch (error) {
      console.error('Failed to create contract client:', error);
      return null;
    }
  }, [contractId, walletNetwork, walletPassphrase]);

  const isReady = contractClient !== null && contractId.trim() !== '';

  return { contractClient, isReady };
};
