import { sha256, sha512 } from "@noble/hashes/sha2";
import { ripemd160 } from "@noble/hashes/legacy";
import {
  Client,
  ECDSA,
  Wallet,
  convertStringToHex,
  encode,
  encodeAccountID,
  encodeForSigning,
  isValidClassicAddress,
  xrpToDrops,
} from "xrpl";
import type { Amount, Payment, TrustSet } from "xrpl";
import type { Asset, NetworkId } from "./assets.ts";
import { CHAIN_NAMES, assetsOf } from "./assets.ts";
import type {
  NfcSigner,
  PaymentChain,
  PaymentRequest,
  PaymentResult,
} from "./types.ts";
import { bytesToHex, hexToBytes, derSignature } from "../lib/bytes.ts";

const NET = {
  testnet: {
    ws: "wss://s.altnet.rippletest.net:51233",
    explorer: "https://testnet.xrpl.org",
  },
  mainnet: {
    ws: "wss://xrplcluster.com",
    explorer: "https://livenet.xrpl.org",
  },
} as const;

/** Generous: a POS only ever needs the line to exist. */
const TRUST_LIMIT = "1000000000";

const FUND_AMOUNT_XRP = "25";

// ponytail: one socket per network per tab; a dropped socket is re-dialed on use.
const sockets = new Map<string, Client>();

async function connect(ws: string): Promise<Client> {
  const open = sockets.get(ws);
  if (open?.isConnected()) return open;
  const client = new Client(ws);
  await client.connect();
  sockets.set(ws, client);
  return client;
}

function compressSec1(raw: Uint8Array): Uint8Array {
  if (raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad SEC1 pubkey");
  return new Uint8Array([
    raw[64]! % 2 === 0 ? 0x02 : 0x03,
    ...raw.slice(1, 33),
  ]);
}

function chipKeys(pubkeyHex: string): {
  address: string;
  signingPubKey: string;
} {
  const compressed = compressSec1(hexToBytes(pubkeyHex));
  return {
    address: encodeAccountID(ripemd160(sha256(compressed))),
    signingPubKey: bytesToHex(compressed).toUpperCase(),
  };
}

/** XRPL wire form: 3-char codes go as-is, longer ones as 40-char hex. */
function currency(code: string): string {
  return code.length === 3
    ? code
    : convertStringToHex(code).padEnd(40, "0").toUpperCase();
}

function amountOf(asset: Asset, value: string): Amount {
  if (!asset.issuer) return xrpToDrops(value);
  return { currency: currency(asset.code), issuer: asset.issuer, value };
}

function resultCode(meta: unknown): string | undefined {
  if (meta && typeof meta === "object" && "TransactionResult" in meta) {
    return String((meta as { TransactionResult: string }).TransactionResult);
  }
  return undefined;
}

function declineMessage(code: string | undefined, asset: Asset): string {
  switch (code) {
    case "tecUNFUNDED_PAYMENT":
    case "tecPATH_DRY":
    case "tecPATH_PARTIAL":
      return `Insufficient ${asset.code} on the card`;
    case "tecNO_LINE":
    case "tecNO_LINE_INSUF_RESERVE":
    case "tecNO_AUTH":
      return `Merchant cannot receive ${asset.code}`;
    case "tecINSUFFICIENT_RESERVE":
      return "Card needs more XRP for the reserve";
    default:
      return `Payment failed: ${code ?? "unknown"}`;
  }
}

/**
 * The chip-signed tail every XRPL transaction shares: autofill, hash, one tap
 * on the card, submit. Both payments and trust lines go through here.
 */
async function submitChipTx(
  rpc: Client,
  tx: Payment | TrustSet,
  signingPubKey: string,
  nfc: NfcSigner,
  describe: (code: string | undefined) => string,
): Promise<string> {
  let prepared;
  try {
    prepared = await rpc.autofill(tx);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (/Account not found|actNotFound/i.test(msg)) {
      throw new Error("Card wallet is unfunded. Settings → Fund chip.");
    }
    throw e;
  }

  const unsigned = { ...prepared, SigningPubKey: signingPubKey };
  const digest = sha512(hexToBytes(encodeForSigning(unsigned))).slice(0, 32);
  const TxnSignature = derSignature(await nfc.signDigest(digest));

  const res = await rpc.submitAndWait(encode({ ...unsigned, TxnSignature }));
  const code = resultCode(res.result.meta);
  if (code !== "tesSUCCESS") throw new Error(describe(code));
  return res.result.hash;
}

export function xrplChain(network: NetworkId): PaymentChain {
  const { ws, explorer } = NET[network];
  const assets = assetsOf(network, "xrpl");
  const testnet = network === "testnet";

  const chain: PaymentChain = {
    id: "xrpl",
    name: CHAIN_NAMES.xrpl,
    network,
    addressHint: "r-address",
    assets,

    isAddress: isValidClassicAddress,

    async balance(address, asset) {
      try {
        const rpc = await connect(ws);
        if (!asset.issuer) {
          const info = await rpc.request({
            command: "account_info",
            account: address,
            ledger_index: "validated",
          });
          const drops = Number(info.result.account_data.Balance);
          return (drops / 1_000_000).toFixed(asset.decimals);
        }
        const lines = await rpc.request({
          command: "account_lines",
          account: address,
          peer: asset.issuer,
          ledger_index: "validated",
        });
        const want = currency(asset.code).toUpperCase();
        const line = lines.result.lines.find(
          (l) => l.currency.toUpperCase() === want,
        );
        return line ? Number(line.balance).toFixed(asset.decimals) : null;
      } catch {
        return null; // no account, or no trust line for this asset
      }
    },

    chipAddress: (sec1Hex) => chipKeys(sec1Hex).address,

    warmUp() {
      void connect(ws).catch(() => {});
    },

    async enableAsset(asset, nfc) {
      if (!asset.issuer) throw new Error(`${asset.code} needs no trust line`);
      const rpc = await connect(ws);
      const { address, signingPubKey } = chipKeys(await nfc.readPublicKey());
      const trust: TrustSet = {
        TransactionType: "TrustSet",
        Account: address,
        LimitAmount: {
          currency: currency(asset.code),
          issuer: asset.issuer,
          value: TRUST_LIMIT,
        },
      };
      await submitChipTx(
        rpc,
        trust,
        signingPubKey,
        nfc,
        (code) => `Could not enable ${asset.code}: ${code ?? "unknown"}`,
      );
    },

    async pay(req: PaymentRequest, nfc: NfcSigner): Promise<PaymentResult> {
      const amount = req.amount.trim();
      if (!amount || Number(amount) <= 0) throw new Error("Enter a valid amount");
      if (req.asset.chain !== "xrpl") {
        throw new Error(`${req.asset.code} is not an XRPL asset`);
      }
      if (!isValidClassicAddress(req.destination)) {
        throw new Error("Set a merchant destination in Settings");
      }

      const rpc = await connect(ws);
      const { address, signingPubKey } = chipKeys(await nfc.readPublicKey());
      const payment: Payment = {
        TransactionType: "Payment",
        Account: address,
        Destination: req.destination,
        Amount: amountOf(req.asset, amount),
      };
      const hash = await submitChipTx(rpc, payment, signingPubKey, nfc, (code) =>
        declineMessage(code, req.asset),
      );

      return {
        hash,
        explorerUrl: `${explorer}/transactions/${hash}`,
        from: address,
        amount,
        symbol: req.asset.code,
      };
    },
  };

  if (!testnet) return chain;

  /** Faucet a throwaway wallet, then pay `address` from it. */
  chain.fund = async (address) => {
    if (!isValidClassicAddress(address)) throw new Error("Invalid XRPL address");
    const rpc = await connect(ws);
    const funder = Wallet.generate(ECDSA.secp256k1);
    await rpc.fundWallet(funder);
    const res = await rpc.submitAndWait(
      funder.sign(
        await rpc.autofill({
          TransactionType: "Payment",
          Account: funder.address,
          Destination: address,
          Amount: xrpToDrops(FUND_AMOUNT_XRP),
        }),
      ).tx_blob,
    );
    const code = resultCode(res.result.meta);
    if (code !== "tesSUCCESS") throw new Error(`Fund failed: ${code}`);
  };

  /** Receive-ready: trust lines are set before the seed goes out of scope. */
  chain.newMerchant = async () => {
    const rpc = await connect(ws);
    const { wallet } = await rpc.fundWallet(Wallet.generate(ECDSA.secp256k1));
    for (const asset of assets) {
      if (!asset.issuer) continue;
      const res = await rpc.submitAndWait(
        wallet.sign(
          await rpc.autofill({
            TransactionType: "TrustSet",
            Account: wallet.address,
            LimitAmount: {
              currency: currency(asset.code),
              issuer: asset.issuer,
              value: TRUST_LIMIT,
            },
          }),
        ).tx_blob,
      );
      const code = resultCode(res.result.meta);
      if (code !== "tesSUCCESS") {
        throw new Error(`${asset.code} trust line failed: ${code}`);
      }
    }
    return { address: wallet.address };
  };

  return chain;
}
