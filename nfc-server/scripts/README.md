# NFC scripts

Tracked scripts for the Infineon NFC bridge.

| Script | Run | Purpose |
|--------|-----|---------|
| `xrpl-nfc-sign.ts` | from `dapp/`: `bun run xrpl-nfc-sign` | XRPL testnet Payment signed by the chip |
| `quick-chip-check.js` | `node scripts/quick-chip-check.js` | Status + pubkey via WS |
| `diagnose-nfc.js` | `node scripts/diagnose-nfc.js` | Status + pubkey + sign via WS |
| `test-ndef-read.js` | `node scripts/test-ndef-read.js` | Read NDEF URL via WS |
| `probe-readers.js` | `node scripts/probe-readers.js` | Direct APDU probe of both Identiv interfaces |
| `direct-chip-check.js` | `node scripts/direct-chip-check.js` | Direct APDU read (no WS; stop server first) |
| `ws-client.js` | (helper) | Shared WebSocket client |

Prereq for diagnostics: start the server first (`node index.js` from `nfc-server/`).
