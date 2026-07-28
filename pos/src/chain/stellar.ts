import {
  Asset as StellarAsset,
  BASE_FEE,
  Horizon,
  Keypair,
  Networks,
  Operation,
  StrKey,
  TransactionBuilder,
} from "@stellar/stellar-sdk";
import type { NetworkId } from "./assets.ts";
import { CHAIN_NAMES, assetsOf } from "./assets.ts";
import type { PaymentChain } from "./types.ts";

const NET = {
  testnet: {
    horizon: "https://horizon-testnet.stellar.org",
    explorer: "https://stellar.expert/explorer/testnet",
    passphrase: Networks.TESTNET,
    friendbot: "https://friendbot.stellar.org",
    /** Soroban RPC, for the Nido invocation once payments land. */
    rpc: import.meta.env.VITE_STELLAR_RPC || "https://soroban-testnet.stellar.org",
  },
  mainnet: {
    horizon: "https://horizon.stellar.org",
    explorer: "https://stellar.expert/explorer/public",
    passphrase: Networks.PUBLIC,
    friendbot: null,
    rpc: import.meta.env.VITE_STELLAR_RPC_MAINNET || "https://mainnet.sorobanrpc.com",
  },
} as const;

export function stellarChain(network: NetworkId): PaymentChain {
  const net = NET[network];
  const assets = assetsOf(network, "stellar");
  const horizon = new Horizon.Server(net.horizon);

  const chain: PaymentChain = {
    id: "stellar",
    name: CHAIN_NAMES.stellar,
    network,
    addressHint: "G-address",
    assets,

    isAddress: (a) => StrKey.isValidEd25519PublicKey(a),

    async balance(address, asset) {
      try {
        const account = await horizon.loadAccount(address);
        const line = account.balances.find((b) =>
          asset.issuer
            ? "asset_code" in b &&
              b.asset_code === asset.code &&
              b.asset_issuer === asset.issuer
            : b.asset_type === "native",
        );
        return line ? Number(line.balance).toFixed(asset.decimals) : null;
      } catch {
        return null; // no account, or no trust line for this asset
      }
    },

    // No chipAddress: a secp256k1 chip cannot own a classic G-account. Stellar
    // payments will run through Nido with the card registered as a signer, see
    // stellar.expert/explorer/testnet/tx/0ae43f38a3ed74aeb1bc3288932535f8aa35d274f98efcc528d19546f19d663c
    // which needs either Nido-side work or a small wrapper contract that
    // understands our chip signing. Everything else here is ready for it.

    pay() {
      return Promise.reject(
        new Error("Stellar needs the card registered on Nido"),
      );
    },
  };

  if (!net.friendbot) return chain;
  const friendbot = net.friendbot;

  const fund = async (address: string) => {
    const res = await fetch(`${friendbot}?addr=${encodeURIComponent(address)}`);
    if (!res.ok) throw new Error(`Friendbot refused: ${res.status}`);
  };
  chain.fund = fund;

  /** Receive-ready: trust lines are set before the secret goes out of scope. */
  chain.newMerchant = async () => {
    const keypair = Keypair.random();
    await fund(keypair.publicKey());

    const issued = assets.filter((a) => a.issuer);
    if (issued.length) {
      const account = await horizon.loadAccount(keypair.publicKey());
      const builder = new TransactionBuilder(account, {
        fee: BASE_FEE,
        networkPassphrase: net.passphrase,
      });
      for (const asset of issued) {
        builder.addOperation(
          Operation.changeTrust({
            asset: new StellarAsset(asset.code, asset.issuer!),
          }),
        );
      }
      const tx = builder.setTimeout(60).build();
      tx.sign(keypair);
      const res = await horizon.submitTransaction(tx);
      if (!res.successful) throw new Error("Trust lines failed");
    }
    return { address: keypair.publicKey() };
  };

  return chain;
}
