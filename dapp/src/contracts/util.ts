import { z } from "zod";
import { WalletNetwork } from "@creit.tech/stellar-wallets-kit";

type NetworkType =
  | "local"
  | "testnet"
  | "pubnet"
  | "futurenet"
  | "mainnet"
  | "custom";
type Network = {
  id: NetworkType;
  label: string;
  horizonUrl: string;
  rpcUrl: string;
  passphrase: string;
};

const envSchema = z.object({
  PUBLIC_STELLAR_NETWORK: z.enum([
    "PUBLIC",
    "FUTURENET",
    "TESTNET",
    "LOCAL",
    "STANDALONE", // deprecated in favor of LOCAL
  ] as const),
  PUBLIC_STELLAR_NETWORK_PASSPHRASE: z.nativeEnum(WalletNetwork),
  PUBLIC_STELLAR_RPC_URL: z.string(),
  PUBLIC_STELLAR_HORIZON_URL: z.string(),
  // Contract IDs for different networks
  PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_LOCAL: z.string().optional(),
  PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_TESTNET: z.string().optional(),
  PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_MAINNET: z.string().optional(),
});

const parsed = envSchema.safeParse(import.meta.env);

const env: z.infer<typeof envSchema> = parsed.success
  ? parsed.data
  : {
      PUBLIC_STELLAR_NETWORK: "LOCAL",
      PUBLIC_STELLAR_NETWORK_PASSPHRASE: WalletNetwork.STANDALONE,
      PUBLIC_STELLAR_RPC_URL: "http://localhost:8000/rpc",
      PUBLIC_STELLAR_HORIZON_URL: "http://localhost:8000",
      PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_LOCAL: undefined,
      PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_TESTNET: undefined,
      PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_MAINNET: undefined,
    };

export const stellarNetwork =
  env.PUBLIC_STELLAR_NETWORK === "STANDALONE"
    ? "LOCAL"
    : env.PUBLIC_STELLAR_NETWORK;
export const networkPassphrase = env.PUBLIC_STELLAR_NETWORK_PASSPHRASE;

const stellarEncode = (str: string) => {
  return str.replace(/\//g, "//").replace(/;/g, "/;");
};

export const labPrefix = () => {
  switch (stellarNetwork) {
    case "LOCAL":
      return `http://localhost:8000/lab/transaction-dashboard?$=network$id=custom&label=Custom&horizonUrl=${stellarEncode(horizonUrl)}&rpcUrl=${stellarEncode(rpcUrl)}&passphrase=${stellarEncode(networkPassphrase)};`;
    case "PUBLIC":
      return `https://lab.stellar.org/transaction-dashboard?$=network$id=mainnet&label=Mainnet&horizonUrl=${stellarEncode(horizonUrl)}&rpcUrl=${stellarEncode(rpcUrl)}&passphrase=${stellarEncode(networkPassphrase)};`;
    case "TESTNET":
      return `https://lab.stellar.org/transaction-dashboard?$=network$id=testnet&label=Testnet&horizonUrl=${stellarEncode(horizonUrl)}&rpcUrl=${stellarEncode(rpcUrl)}&passphrase=${stellarEncode(networkPassphrase)};`;
    case "FUTURENET":
      return `https://lab.stellar.org/transaction-dashboard?$=network$id=futurenet&label=Futurenet&horizonUrl=${stellarEncode(horizonUrl)}&rpcUrl=${stellarEncode(rpcUrl)}&passphrase=${stellarEncode(networkPassphrase)};`;
    default:
      return `https://lab.stellar.org/transaction-dashboard?$=network$id=testnet&label=Testnet&horizonUrl=${stellarEncode(horizonUrl)}&rpcUrl=${stellarEncode(rpcUrl)}&passphrase=${stellarEncode(networkPassphrase)};`;
  }
};

// NOTE: needs to be exported for contract files in this directory
export const rpcUrl = env.PUBLIC_STELLAR_RPC_URL;

export const horizonUrl = env.PUBLIC_STELLAR_HORIZON_URL;

const networkToId = (network: string): NetworkType => {
  switch (network) {
    case "PUBLIC":
      return "mainnet";
    case "TESTNET":
      return "testnet";
    case "FUTURENET":
      return "futurenet";
    default:
      return "custom";
  }
};

export const network: Network = {
  id: networkToId(stellarNetwork),
  label: stellarNetwork.toLowerCase(),
  passphrase: networkPassphrase,
  rpcUrl: rpcUrl,
  horizonUrl: horizonUrl,
};

/**
 * Get RPC URL based on network
 */
export const getRpcUrl = (walletNetwork?: string): string => {
  const networkToUse = (walletNetwork || stellarNetwork).toUpperCase();

  switch (networkToUse) {
    case "LOCAL":
    case "STANDALONE":
      return "http://localhost:8000/rpc";
    case "TESTNET":
      return "https://soroban-testnet.stellar.org";
    case "PUBLIC":
    case "MAINNET":
      return "https://soroban-mainnet.stellar.org";
    case "FUTURENET":
      return "https://soroban-futurenet.stellar.org";
    default:
      return "http://localhost:8000/rpc";
  }
};

/**
 * Get Horizon URL based on network
 */
export const getHorizonUrl = (walletNetwork?: string): string => {
  const networkToUse = (walletNetwork || stellarNetwork).toUpperCase();

  switch (networkToUse) {
    case "LOCAL":
    case "STANDALONE":
      return "http://localhost:8000";
    case "TESTNET":
      return "https://horizon-testnet.stellar.org";
    case "PUBLIC":
    case "MAINNET":
      return "https://horizon.stellar.org";
    case "FUTURENET":
      return "https://horizon-futurenet.stellar.org";
    default:
      return "http://localhost:8000";
  }
};

/**
 * Get network passphrase based on network
 */
export const getNetworkPassphrase = (
  walletNetwork?: string,
  walletPassphrase?: string,
): string => {
  // If wallet provides passphrase, use it (most reliable)
  if (walletPassphrase) {
    return walletPassphrase;
  }

  const networkToUse = (walletNetwork || stellarNetwork).toUpperCase();

  switch (networkToUse) {
    case "LOCAL":
    case "STANDALONE":
      return "Standalone Network ; February 2017";
    case "TESTNET":
      return "Test SDF Network ; September 2015";
    case "PUBLIC":
    case "MAINNET":
      return "Public Global Stellar Network ; September 2015";
    case "FUTURENET":
      return "Test SDF Future Network ; October 2022";
    default:
      return "Standalone Network ; February 2017";
  }
};

/**
 * Get contract ID based on network
 * Uses wallet's network if provided, otherwise falls back to app's configured network
 * Network names are normalized to uppercase for consistent matching
 */
export const getContractId = (walletNetwork?: string): string => {
  const networkToUse = (walletNetwork || stellarNetwork).toUpperCase();

  let contractId: string | undefined;
  let envVarName: string;

  switch (networkToUse) {
    case "LOCAL":
    case "STANDALONE":
      contractId = env.PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_LOCAL;
      envVarName = "PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_LOCAL";
      break;
    case "TESTNET":
      contractId = env.PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_TESTNET;
      envVarName = "PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_TESTNET";
      break;
    case "PUBLIC":
    case "MAINNET":
      contractId = env.PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_MAINNET;
      envVarName = "PUBLIC_STELLAR_MERCH_SHOP_CONTRACT_ID_MAINNET";
      break;
    default:
      throw new Error(
        `Unknown network: ${networkToUse}. Supported networks: LOCAL, TESTNET, PUBLIC, MAINNET`,
      );
  }

  if (!contractId || contractId.trim() === "") {
    throw new Error(
      `Contract ID is not configured for network ${networkToUse}. Please set ${envVarName} environment variable.`,
    );
  }

  // After the check, contractId is guaranteed to be a non-empty string
  // TypeScript should narrow, but we assert to be explicit
  return contractId as string;
};
