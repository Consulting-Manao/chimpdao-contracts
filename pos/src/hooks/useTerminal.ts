import { useCallback, useState } from "react";
import type { ChainId, NetworkId } from "../chain/assets.ts";
import { defaultAsset, findAsset } from "../chain/assets.ts";
import { CHAINS, chainFor } from "../chain/index.ts";

const NETWORK_KEY = "chimp.network";
const ASSET_KEY = "chimp.asset";
const merchantKey = (n: NetworkId, c: ChainId) => `chimp.merchant.${n}.${c}`;

// ponytail: the pre-multichain single-merchant key, read once so an already
// funded testnet merchant survives the upgrade. Delete after the demo terminals
// have written their new keys.
const LEGACY_MERCHANT_KEY = "chimpdao-pos-merchant";

function readNetwork(): NetworkId {
  return localStorage.getItem(NETWORK_KEY) === "mainnet" ? "mainnet" : "testnet";
}

function readMerchants(network: NetworkId): Record<ChainId, string> {
  const entries = CHAINS.map((chain) => {
    const stored = localStorage.getItem(merchantKey(network, chain));
    const legacy =
      network === "testnet" && chain === "xrpl"
        ? localStorage.getItem(LEGACY_MERCHANT_KEY)
        : null;
    return [chain, stored || legacy || ""];
  });
  return Object.fromEntries(entries) as Record<ChainId, string>;
}

/**
 * The two axes the terminal runs on: a network the operator picks in Settings,
 * and the asset the customer pays with. Merchant addresses hang off both, since
 * an r-address on testnet is not the one you want on mainnet.
 */
export function useTerminal() {
  const [network, setNetworkState] = useState(readNetwork);
  const [assetId, setAssetIdState] = useState(
    () => localStorage.getItem(ASSET_KEY) ?? "",
  );
  const [merchants, setMerchants] = useState(() => readMerchants(readNetwork()));

  const stored = findAsset(network, assetId);
  const asset = stored && !stored.unavailable ? stored : defaultAsset(network);
  const chain = chainFor(asset.chain, network);

  const setNetwork = useCallback((next: NetworkId) => {
    localStorage.setItem(NETWORK_KEY, next);
    setMerchants(readMerchants(next));
    setNetworkState(next);
  }, []);

  const setAsset = useCallback((id: string) => {
    localStorage.setItem(ASSET_KEY, id);
    setAssetIdState(id);
  }, []);

  const setMerchant = useCallback(
    (chainId: ChainId, address: string) => {
      const value = address.trim();
      const key = merchantKey(network, chainId);
      if (value) localStorage.setItem(key, value);
      else localStorage.removeItem(key);
      setMerchants((prev) => ({ ...prev, [chainId]: value }));
    },
    [network],
  );

  return {
    network,
    setNetwork,
    asset,
    setAsset,
    chain,
    destination: merchants[asset.chain],
    merchants,
    setMerchant,
  };
}
