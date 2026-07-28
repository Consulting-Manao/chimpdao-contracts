# Chi//mp POS

Tap-to-pay terminal for **ChimpDAO**: the Infineon NFC chip is the customer smart wallet; it single-signs an XRPL Payment to the merchant.

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

## Demo flow

1. Gear icon → **Settings**: check the network, reader and chip rows
2. **Create & fund** (merchant on XRPL testnet), then place chip → **Fund chip**
3. Back to Pay → enter amount → **Charge** → hold chip → explorer link
4. Settings → **Payments** lists the sales, newest first, with a receipt link

Chip pays. Merchant receives. Funding is explicit and testnet-only.

## Stack

- Vite + React + TypeScript + `xrpl`
- Chain adapter in `src/chain/` (`xrpl` today; swap later for XLM)
- History in `src/lib/history.ts`: `localStorage`, records keyed `chain:hash`,
  written through `mergeRecords` so an RPC back-fill can use the same entry point
- Thin NFC WebSocket client → `nfc-server` on `:8080`
