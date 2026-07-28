export type NetworkId = "testnet" | "mainnet";
export type ChainId = "xrpl" | "stellar";

/**
 * One thing a customer can pay with. Chain and token travel together so the
 * terminal needs a single selector, and a future swap layer only has to map one
 * of these onto another.
 */
export type Asset = {
  /** Stable across networks; history and the picker key off it. */
  id: string;
  chain: ChainId;
  code: string;
  /** Absent for native assets. */
  issuer?: string;
  /** Keypad limit. */
  decimals: number;
  /** Testnet only: where the operator tops this asset up by hand. */
  faucet?: string;
  /** Why it can't be paid yet; drop the line when it goes live. */
  unavailable?: string;
};

export const CHAIN_NAMES: Record<ChainId, string> = {
  xrpl: "XRPL",
  stellar: "Stellar",
};

/** The card has to be registered as a signer on Nido before Stellar can pay. */
const NIDO = "Coming soon";

const RLUSD = "RLUSD";
const USDC = "USDC";

const REGISTRY: Record<NetworkId, Asset[]> = {
  testnet: [
    { id: "xrpl:XRP", chain: "xrpl", code: "XRP", decimals: 6 },
    {
      id: "xrpl:RLUSD",
      chain: "xrpl",
      code: RLUSD,
      issuer: "rQhWct2fv4Vc4KRjRgMrxa8xPN9Zx9iLKV",
      decimals: 2,
      faucet: "https://tryrlusd.com/",
    },
    {
      id: "stellar:XLM",
      chain: "stellar",
      code: "XLM",
      decimals: 7,
      unavailable: NIDO,
    },
    {
      id: "stellar:USDC",
      chain: "stellar",
      code: USDC,
      issuer: "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
      decimals: 2,
      faucet: "https://faucet.circle.com/",
      unavailable: NIDO,
    },
  ],
  mainnet: [
    { id: "xrpl:XRP", chain: "xrpl", code: "XRP", decimals: 6 },
    {
      id: "xrpl:RLUSD",
      chain: "xrpl",
      code: RLUSD,
      issuer: "rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De",
      decimals: 2,
    },
    {
      id: "stellar:XLM",
      chain: "stellar",
      code: "XLM",
      decimals: 7,
      unavailable: NIDO,
    },
    {
      id: "stellar:USDC",
      chain: "stellar",
      code: USDC,
      issuer: "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN",
      decimals: 2,
      unavailable: NIDO,
    },
  ],
};

export function assetsFor(network: NetworkId): Asset[] {
  return REGISTRY[network];
}

export function assetsOf(network: NetworkId, chain: ChainId): Asset[] {
  return REGISTRY[network].filter((a) => a.chain === chain);
}

export function findAsset(network: NetworkId, id: string): Asset | undefined {
  return REGISTRY[network].find((a) => a.id === id);
}

/** What the terminal falls back to: the first asset that can actually pay. */
export function defaultAsset(network: NetworkId): Asset {
  const asset = REGISTRY[network].find((a) => !a.unavailable);
  if (!asset) throw new Error(`No payable asset on ${network}`);
  return asset;
}

// ponytail: assert the registry can't ship duplicate ids or an issuer-less token
if (import.meta.env.DEV) {
  for (const network of ["testnet", "mainnet"] as NetworkId[]) {
    const assets = assetsFor(network);
    const ids = new Set(assets.map((a) => a.id));
    if (ids.size !== assets.length) console.warn(`${network}: duplicate asset id`);
    for (const a of assets) {
      if (a.code !== "XRP" && a.code !== "XLM" && !a.issuer) {
        console.warn(`${network}: ${a.code} has no issuer`);
      }
      if (network === "mainnet" && a.faucet) {
        console.warn(`mainnet: ${a.code} must not carry a faucet`);
      }
    }
  }
}
