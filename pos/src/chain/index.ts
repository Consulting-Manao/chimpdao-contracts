import type { ChainId, NetworkId } from "./assets.ts";
import { stellarChain } from "./stellar.ts";
import type { PaymentChain } from "./types.ts";
import { xrplChain } from "./xrpl.ts";

export const CHAINS: ChainId[] = ["xrpl", "stellar"];

const BUILDERS: Record<ChainId, (network: NetworkId) => PaymentChain> = {
  xrpl: xrplChain,
  stellar: stellarChain,
};

// Memoized so a chain keeps its warmed-up connection across renders.
const bound = new Map<string, PaymentChain>();

export function chainFor(chain: ChainId, network: NetworkId): PaymentChain {
  const key = `${chain}:${network}`;
  let instance = bound.get(key);
  if (!instance) {
    instance = BUILDERS[chain](network);
    bound.set(key, instance);
  }
  return instance;
}
