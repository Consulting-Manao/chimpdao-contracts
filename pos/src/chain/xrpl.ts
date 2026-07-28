import { sha256, sha512 } from "@noble/hashes/sha2";
import { ripemd160 } from "@noble/hashes/legacy";
import {
  Client,
  encode,
  encodeForSigning,
  encodeAccountID,
  xrpToDrops,
} from "xrpl";
import type { PaymentChain, PaymentRequest, PaymentResult, NfcSigner } from "./types.ts";
import { bytesToHex, hexToBytes, derSignature } from "../lib/bytes.ts";

const XRPL_WS =
  import.meta.env.VITE_XRPL_WS || "wss://s.altnet.rippletest.net:51233";
const EXPLORER = "https://testnet.xrpl.org";

let shared: Client | null = null;

async function client(): Promise<Client> {
  // ponytail: one socket per tab; a dropped socket is re-dialed on next use.
  if (shared?.isConnected()) return shared;
  shared = new Client(XRPL_WS);
  await shared.connect();
  return shared;
}

export function compressSec1(raw: Uint8Array): Uint8Array {
  if (raw.length !== 65 || raw[0] !== 0x04) throw new Error("bad SEC1 pubkey");
  return new Uint8Array([
    raw[64]! % 2 === 0 ? 0x02 : 0x03,
    ...raw.slice(1, 33),
  ]);
}

export function addressFromCompressed(compressed: Uint8Array): string {
  return encodeAccountID(ripemd160(sha256(compressed)));
}

export function addressFromSec1Hex(pubkeyHex: string): {
  address: string;
  signingPubKey: string;
} {
  const compressed = compressSec1(hexToBytes(pubkeyHex));
  return {
    address: addressFromCompressed(compressed),
    signingPubKey: bytesToHex(compressed).toUpperCase(),
  };
}

export async function getXrpBalance(address: string): Promise<string | null> {
  try {
    const info = await (await client()).request({
      command: "account_info",
      account: address,
      ledger_index: "validated",
    });
    return (Number(info.result.account_data.Balance) / 1_000_000).toFixed(6);
  } catch {
    return null;
  }
}

export const xrplChain: PaymentChain = {
  id: "xrpl",
  symbol: "XRP",
  networkLabel: "XRPL Testnet",

  warmUp() {
    void client().catch(() => {});
  },

  async pay(req: PaymentRequest, nfc: NfcSigner): Promise<PaymentResult> {
    const amount = req.amount.trim();
    if (!amount || Number(amount) <= 0) throw new Error("Enter a valid amount");
    if (!req.destination?.startsWith("r")) {
      throw new Error("Set a merchant destination in Settings");
    }

    const rpc = await client();

    const { address: chipAddress, signingPubKey } = addressFromSec1Hex(
      await nfc.readPublicKey(),
    );

    let prepared;
    try {
      prepared = await rpc.autofill({
        TransactionType: "Payment",
        Account: chipAddress,
        Destination: req.destination,
        Amount: xrpToDrops(amount),
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (/Account not found|actNotFound/i.test(msg)) {
        throw new Error("Chip wallet is unfunded. Settings → Fund chip.");
      }
      throw e;
    }

    const unsigned = { ...prepared, SigningPubKey: signingPubKey };
    const digest = sha512(hexToBytes(encodeForSigning(unsigned))).slice(0, 32);

    const txnSignature = derSignature(await nfc.signDigest(digest));

    const result = await rpc.submitAndWait(
      encode({ ...unsigned, TxnSignature: txnSignature }),
    );
    const meta = result.result.meta;
    const code =
      meta && typeof meta === "object" && "TransactionResult" in meta
        ? String(meta.TransactionResult)
        : undefined;
    if (code !== "tesSUCCESS") {
      if (code === "tecUNFUNDED_PAYMENT") {
        throw new Error("Chip has insufficient XRP. Settings → Fund chip.");
      }
      throw new Error(`Payment failed: ${code ?? "unknown"}`);
    }

    const hash = result.result.hash;
    return {
      hash,
      explorerUrl: `${EXPLORER}/transactions/${hash}`,
      from: chipAddress,
      amount,
      symbol: "XRP",
    };
  },
};
