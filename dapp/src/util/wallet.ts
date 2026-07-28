import storage from "./storage.ts";
import { StellarWalletsKit } from "@creit.tech/stellar-wallets-kit/sdk";
import { sep43Modules } from "@creit.tech/stellar-wallets-kit/modules/utils";
import { Networks } from "@creit.tech/stellar-wallets-kit/types";
import { Horizon } from "@stellar/stellar-sdk";
import { networkPassphrase, stellarNetwork } from "../contracts/util.ts";

StellarWalletsKit.init({
  network: networkPassphrase as Networks,
  modules: sep43Modules(),
});

export const connectWallet = async () => {
  const { address } = await StellarWalletsKit.authModal();

  const selectedId = StellarWalletsKit.selectedModule?.productId;
  if (address) {
    storage.setItem("walletAddress", address);
    if (selectedId) storage.setItem("walletId", selectedId);
  } else {
    storage.setItem("walletId", "");
    storage.setItem("walletAddress", "");
  }

  if (selectedId === "freighter" || selectedId === "hot-wallet") {
    try {
      const network = await StellarWalletsKit.getNetwork();
      if (network.network && network.networkPassphrase) {
        storage.setItem("walletNetwork", network.network);
        storage.setItem("networkPassphrase", network.networkPassphrase);
      } else {
        storage.setItem("walletNetwork", "");
        storage.setItem("networkPassphrase", "");
      }
    } catch (e) {
      console.error(e);
    }
  }
};

export const disconnectWallet = async () => {
  await StellarWalletsKit.disconnect();
  storage.removeItem("walletId");
};

function getHorizonHost(mode: string) {
  switch (mode) {
    case "LOCAL":
    case "STANDALONE":
      return "http://localhost:8000";
    case "FUTURENET":
      return "https://horizon-futurenet.stellar.org";
    case "TESTNET":
      return "https://horizon-testnet.stellar.org";
    case "PUBLIC":
    case "MAINNET":
      return "https://horizon.stellar.org";
    default:
      throw new Error(`Unknown Stellar network: ${mode}`);
  }
}

const formatter = new Intl.NumberFormat();

export type MappedBalances = Record<string, Horizon.HorizonApi.BalanceLine>;

/**
 * Fetch balances for an address on a specific network
 * @param address - The Stellar address to fetch balances for
 * @param network - Optional network name (e.g., "TESTNET", "PUBLIC", "LOCAL"). Uses app's configured network if not provided.
 */
export const fetchBalances = async (address: string, network?: string) => {
  try {
    // Use wallet's network if provided, otherwise fall back to app's configured network
    const networkToUse = (network || stellarNetwork).toUpperCase();
    const horizonUrl = getHorizonHost(networkToUse);
    const horizon = new Horizon.Server(horizonUrl, {
      allowHttp: networkToUse === "LOCAL" || networkToUse === "STANDALONE",
    });

    const { balances } = await horizon.accounts().accountId(address).call();
    const mapped = balances.reduce((acc, b) => {
      b.balance = formatter.format(Number(b.balance));
      const key =
        b.asset_type === "native"
          ? "xlm"
          : b.asset_type === "liquidity_pool_shares"
            ? b.liquidity_pool_id
            : `${b.asset_code}:${b.asset_issuer}`;
      acc[key] = b;
      return acc;
    }, {} as MappedBalances);
    return mapped;
  } catch (err) {
    // `not found` is sort of expected, indicating an unfunded wallet, which
    // the consumer of `balances` can understand via the lack of `xlm` key.
    // If the error does NOT match 'not found', log the error.
    // We should also possibly not return `{}` in this case?
    if (!(err instanceof Error && err.message.match(/not found/i))) {
      console.error(err);
    }
    return {};
  }
};

export { StellarWalletsKit };
