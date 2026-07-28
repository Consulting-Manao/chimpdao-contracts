import { xrplChain } from "./xrpl.ts";
import type { PaymentChain } from "./types.ts";

const chainId = import.meta.env.VITE_CHAIN || "xrpl";

if (chainId !== "xrpl") throw new Error(`Unsupported chain: ${chainId}`);

export const activeChain: PaymentChain = xrplChain;

export type {
  PaymentChain,
  PaymentRequest,
  PaymentResult,
  NfcSigner,
} from "./types.ts";
