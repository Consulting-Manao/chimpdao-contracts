export type PaymentRequest = {
  amount: string;
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
  chain: string;
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

export interface PaymentChain {
  id: "xrpl";
  symbol: string;
  networkLabel: string;
  /** Open the network connection ahead of the tap so the card is held for less time. */
  warmUp?(): void;
  pay(req: PaymentRequest, nfc: NfcSigner): Promise<PaymentResult>;
}
