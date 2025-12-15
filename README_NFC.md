# NFC Chip Integration Guide

Complete guide for using Infineon SECORA Blockchain NFC chips with Stellar Merch Shop to mint NFTs linked to physical products.

## Overview

This application integrates Infineon NFC chips for NFT operations on desktop:
- **Desktop**: USB NFC reader (uTrust 4701F) via WebSocket server
- **Authentication**: SEP-53 compliant contract auth
- **Security**: Hardware-secured signatures via secp256k1

## Prerequisites

- **Hardware**: Infineon SECORA Blockchain NFC chip + uTrust 4701F reader (for Desktop)
- **Software**: Node.js, Python with `blocksec2go` package
- **Wallet**: Freighter or compatible Stellar wallet

## Running

```bash
# Terminal 1: NFC Server
cd nfc-server
node index.js

# Terminal 2: Dev Server
bun run dev
```

Or start everything together:
```bash
bun run dev:with-nfc
```

## How It Works

### Architecture

**Desktop**:
```
Browser ← WebSocket → NFC Server ← blocksec2go → USB Reader ← NFC → Chip
```

### Flow

1. **Read Chip**: Get chip's public key (65-byte secp256k1 key)
2. **Fetch Ledger**: Get current ledger number from Horizon API for SEP-53 expiry
3. **Create Message**: Build SEP-53 auth message
4. **Hash**: Compute SHA-256 hash of message
5. **Sign**: Chip signs the 32-byte hash
6. **Detect Recovery ID**: Server provides recovery ID (loop over 0 to 3)
7. **Contract Call**: Send original message + signature + detected recovery ID to contract
8. **Verify**: Contract hashes message and recovers public key via `secp256k1_recover`
9. **Token ID**: Recovered public key becomes the NFT token ID

### SEP-53 Authentication

Uses [SEP-53](https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0053.md) standard format:
```
message = network_hash + contract_id + function_name + args + nonce
```

## Technical Details

### Signature Format
- **From chip**: DER-encoded ECDSA signature
- **Parsed**: r (32 bytes) + s (32 bytes)
- **Normalized**: s must be in "low form" (s < curve_order/2)
- **Recovery ID**: Defaults to 1 for Infineon SECORA chips

### blocksec2go Commands
```bash
# Get card info
blocksec2go get_card_info

# Get public key (key index 1)
blocksec2go get_key_info 1

# Sign 32-byte hash (key index 1)
blocksec2go generate_signature 1 <32-byte-hex>
```
