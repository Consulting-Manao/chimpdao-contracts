# NFC Chip Integration Guide

Complete guide for using Infineon SECORA Blockchain NFC chips with the Stellar dapp and the XRPL POC to mint/claim/transfer NFTs or sign XRPL testnet transactions from a physical chip.

## Overview

This application integrates Infineon NFC chips for desktop crypto operations:

- **Desktop**: USB NFC reader (uTrust 4701F) via a Node.js WebSocket server
- **Chains**: Stellar Soroban (SEP-53 contract auth) + XRPL testnet (single-sign chip demo)
- **Security**: Hardware-secured ECDSA signatures over secp256k1

## Prerequisites

- **Hardware**: Infineon SECORA Blockchain NFC chip + uTrust 4701F reader (Desktop)
- **Software**: Node.js >= 22 for the NFC server; Bun for the dapp/XRPL script
- **Wallet**: Freighter or compatible Stellar wallet (Stellar only)

## Running

```bash
# Terminal 1: NFC Server (must run with Node, not Bun)
cd nfc-server
node index.js

# Terminal 2: Stellar dev server
cd dapp
bun run dev

# Or start everything together:
bun run dev:with-nfc
```

### Chi//mp POS (XRPL tap-to-pay)

Standalone POS UI at [`pos/`](pos/): amount → tap chip → chip-signed XRPL Payment.

```bash
# Terminal 1: NFC server
cd nfc-server && node index.js

# Terminal 2: POS
cd pos && bun install && bun run dev
# → http://localhost:5174
```

Wallet tab: create/fund merchant + fund chip (testnet faucet). Pay tab never auto-funds.

### XRPL one-shot script

```bash
cd dapp
bun run xrpl-nfc-sign
```

(Script lives at `nfc-server/scripts/xrpl-nfc-sign.ts`.)

## How It Works

### Architecture

```
Browser ← WebSocket → NFC Server ← nfc-pcsc → USB Reader ← NFC → Chip
        ↑
        └── XRPL script
```

The NFC server is a small `nfc-pcsc` bridge over WebSocket. It exposes APDU operations (`read-pubkey`, `sign`, `read-ndef`, `write-ndef`, `generate-key`, `fetch-key`) and is used by both the Stellar dapp and the XRPL POC.

### Stellar flow

1. **Read chip**: get the 65-byte secp256k1 public key
2. **Fetch nonce**: current chip nonce for SEP-53 expiry
3. **Create message**: build SEP-53 auth message (`network_hash + contract_id + function_name + args + nonce`)
4. **Hash**: SHA-256 hash of the message
5. **Sign**: chip signs the 32-byte hash
6. **Detect recovery ID**: client-side (`@noble/secp256k1`) recovers the recovery ID from the signature
7. **Contract call**: send message + `r||s` signature + recovery ID to the Soroban contract
8. **Verify**: contract hashes the message and recovers the public key via `secp256k1_recover`

### XRPL flow

1. **Read chip**: get the 65-byte public key
2. **Compress**: 65-byte SEC1 → 33-byte compressed pubkey
3. **Derive address**: `encodeAccountID(RIPEMD160(SHA256(compressed)))`
4. **Fund chip**: faucet wallet sends testnet XRP to the chip address
5. **Build Payment**: chip address as sender, `SigningPubKey` set
6. **Hash**: `encodeForSigning` + SHA-512Half (first 32 bytes of SHA-512)
7. **Sign**: chip signs the 32-byte hash
8. **Re-DER**: raw 64-byte `r||s` → DER → `TxnSignature`
9. **Submit**: `encode(...)` + `submitAndWait`

## Technical Details

### Signature format

- **From chip**: DER-encoded ECDSA signature
- **From server**: `r` (32 bytes) + `s` (32 bytes) as hex strings, low-S normalized
- **Stellar consumer**: client recomputes recovery ID; signature is `r||s` + recovery ID
- **XRPL consumer**: `r||s` is re-encoded into DER for `TxnSignature`

### blocksec2go diagnostic commands (optional)

These are only used for regenerating contract test signatures, not the server runtime:

```bash
# Get card info
blocksec2go get_card_info

# Get public key (key index 1)
blocksec2go get_key_info 1

# Sign 32-byte hash (key index 1)
blocksec2go generate_signature 1 <32-byte-hex>
```

### Regenerating NFC test signatures

To update the 5 test signatures and chip public keys in `contracts/nfc-nft` (e.g. after changing the message hash or rotating chips), follow the one-shot instructions in **[dapp/scripts/REGENERATE_NFC_TEST_SIGS.md](dapp/scripts/REGENERATE_NFC_TEST_SIGS.md)**.
