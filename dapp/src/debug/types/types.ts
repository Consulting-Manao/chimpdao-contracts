export type NetworkType =
  | "local"
  | "testnet"
  | "pubnet"
  | "futurenet"
  | "mainnet"
  | "custom";

export type Network = {
  id: NetworkType;
  label: string;
  horizonUrl: string;
  rpcUrl: string;
  passphrase: string;
};
