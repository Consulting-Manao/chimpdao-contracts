import { Client, Wallet, xrpToDrops, ECDSA } from "xrpl";

const XRPL_WS =
  import.meta.env.VITE_XRPL_WS || "wss://s.altnet.rippletest.net:51233";

const FUND_AMOUNT_XRP = "25";

function txResult(meta: unknown): string | undefined {
  if (meta && typeof meta === "object" && "TransactionResult" in meta) {
    return String((meta as { TransactionResult: string }).TransactionResult);
  }
  return undefined;
}

/** Faucet a throwaway wallet, then Payment to `address`. */
export async function fundAddress(
  address: string,
): Promise<{ hash: string }> {
  if (!address.startsWith("r")) throw new Error("Invalid XRPL address");

  const client = new Client(XRPL_WS);
  try {
    await client.connect();
    const funder = Wallet.generate(ECDSA.secp256k1);
    await client.fundWallet(funder);

    const funded = await client.submitAndWait(
      funder.sign(
        await client.autofill({
          TransactionType: "Payment",
          Account: funder.address,
          Destination: address,
          Amount: xrpToDrops(FUND_AMOUNT_XRP),
        }),
      ).tx_blob,
    );

    const code = txResult(funded.result.meta);
    if (code !== "tesSUCCESS") {
      throw new Error(`Fund failed: ${code ?? "unknown"}`);
    }
    return { hash: funded.result.hash };
  } finally {
    await client.disconnect();
  }
}

/** Create a new merchant account and faucet-fund it (testnet). */
export async function createAndFundMerchant(): Promise<{ address: string }> {
  const client = new Client(XRPL_WS);
  try {
    await client.connect();
    const w = Wallet.generate(ECDSA.secp256k1);
    const { wallet } = await client.fundWallet(w);
    return { address: wallet.address };
  } finally {
    await client.disconnect();
  }
}
