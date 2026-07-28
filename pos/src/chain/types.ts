import type { Asset, ChainId, NetworkId } from "./assets.ts";

export type PaymentRequest = {
  amount: string;
  asset: Asset;
  destination: string;
};

export type PaymentResult = {
  hash: string;
  explorerUrl: string;
  from: string;
  amount: string;
  symbol: string;
};

/**
 * One completed payment. Deliberately chain- and token-agnostic: local sales
 * and, later, transactions pulled from an RPC must both fit this shape.
 */
export type PaymentRecord = {
  /** `${chain}:${hash}` — stable across sources, so a pull can dedupe. */
  id: string;
  chain: ChainId;
  /** Absent on records written before the network was selectable. */
  network?: NetworkId;
  hash: string;
  from: string;
  to: string;
  amount: string;
  symbol: string;
  /** Issuer or contract for non-native tokens; absent for XRP, XLM and friends. */
  asset?: string;
  /** Epoch ms. Local clock today, ledger close time once pulled from an RPC. */
  at: number;
  explorerUrl: string;
};

export type NfcSigner = {
  readPublicKey(): Promise<string>;
  signDigest(digest: Uint8Array): Promise<Uint8Array>;
};

/**
 * A chain bound to one network. Optional members are how a chain says "not yet":
 * the UI renders from their presence instead of branching on chain ids, and a
 * mainnet instance simply omits the faucets.
 */
export interface PaymentChain {
  id: ChainId;
  name: string;
  network: NetworkId;
  /** Placeholder for the paste field, e.g. "r-address". */
  addressHint: string;
  assets: Asset[];
  isAddress(a: string): boolean;
  /** null = this address can't hold the asset (no account, or no trust line). */
  balance(address: string, asset: Asset): Promise<string | null>;
  /** Only chains that can turn the chip's secp256k1 key into an account. */
  chipAddress?(sec1Hex: string): string;
  /** Testnet only. */
  fund?(address: string): Promise<void>;
  /** A fresh account able to receive every asset on this network. */
  newMerchant?(): Promise<{ address: string }>;
  /** Chip-signed trust line; needs a tap. */
  enableAsset?(asset: Asset, nfc: NfcSigner): Promise<void>;
  /** Open the network connection ahead of the tap so the card is held for less time. */
  warmUp?(): void;
  pay(req: PaymentRequest, nfc: NfcSigner): Promise<PaymentResult>;
}
