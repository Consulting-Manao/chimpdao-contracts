# Chi//mp POS

Tap-to-pay terminal for **ChimpDAO**: the Infineon NFC chip is the customer smart wallet; it single-signs the payment to the merchant.

## Prerequisites

1. Identiv USB reader + chip
2. NFC bridge: from repo root / dapp —

```bash
cd nfc-server && node index.js
# or: cd dapp && bun run nfc-server
```

## Run

```bash
cd pos
bun install
cp .env.example .env   # optional
bun run dev            # http://localhost:5174
```

## Networks and assets

The terminal runs on two axes:

- **Network** (`Testnet | Mainnet`) is an operator choice in Settings. Chain
  adapters are built for a network, so mainnet has no faucet methods and every
  funding button disappears on its own.
- **Asset** is a customer choice on the pay screen: the pill next to the amount
  picks chain and token in one control.

| Asset | Chain   | Pays today                       |
| ----- | ------- | -------------------------------- |
| XRP   | XRPL    | yes                              |
| RLUSD | XRPL    | yes (trust line on both sides)   |
| XLM   | Stellar | no — card must be a Nido signer  |
| USDC  | Stellar | no — card must be a Nido signer  |

Stellar merchant setup is live (friendbot funding, USDC trust line, balances);
only `pay()` waits on the card being registered as a signer on Nido, since a
secp256k1 chip cannot own a classic G-account.

## Demo flow

1. Gear icon → **Settings**: network toggle, reader and chip rows
2. **Create & fund** a merchant per chain — created accounts come back with the
   trust lines they need to receive stablecoins
3. Place the chip → **Fund chip** for XRP, **Enable** for RLUSD (needs a tap),
   then top the card up from the faucet link
4. Back to Pay → pick the asset → enter amount → **Charge** → hold the chip
5. Settings → **Payments** lists every sale, newest first, with a receipt link

Chip pays. Merchant receives. Funding is explicit and testnet-only.

## Stack

- Vite + React + TypeScript, `xrpl` and `@stellar/stellar-sdk`
- `src/chain/assets.ts` is the asset registry; `chainFor(chain, network)` builds
  a memoized adapter. Optional adapter members (`fund`, `newMerchant`,
  `enableAsset`, `chipAddress`) are what the UI renders from, so no screen
  branches on a chain id
- History in `src/lib/history.ts`: `localStorage`, records keyed `chain:hash`,
  written through `mergeRecords` so an RPC back-fill can use the same entry point
- Thin NFC WebSocket client → `nfc-server` on `:8080`
