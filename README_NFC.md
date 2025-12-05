# NFC Chip Integration Guide

Complete guide for using Infineon SECORA Blockchain NFC chips with Stellar Merch Shop to mint NFTs linked to physical products.

## Overview

This application integrates Infineon NFC chips for NFT minting on desktop:
- **Desktop**: USB NFC reader (uTrust 4701F) via WebSocket server
- **Authentication**: SEP-53 compliant contract auth
- **Security**: Hardware-secured signatures via secp256k1

**Note**: This is a desktop-only admin tool for chip initialization and management. For mobile minting, use the standalone iOS app (see `NFCBridge/` directory).

## Quick Start

### Prerequisites

- **Hardware**: Infineon SECORA Blockchain NFC chip + uTrust 4701F reader (for Desktop)
- **Software**: Node.js, Bun, Python with `blocksec2go` package
- **Wallet**: Freighter or compatible Stellar wallet

### Installation

```bash
# Install main dependencies
bun install

# Install NFC server
cd nfc-server
bun install ws
cd ..

# Create environment file
echo "VITE_STELLAR_NETWORK=testnet" > .env
```

### Running

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

Open browser at http://localhost:5173

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
6. **Detect Recovery ID**: Server provides recovery ID (default: 1 for Infineon chips)
7. **Contract Call**: Send original message + signature + detected recovery ID to contract
8. **Verify**: Contract hashes message and recovers public key via `secp256k1_recover`
9. **Token ID**: Recovered public key becomes the NFT token ID

### SEP-53 Authentication

Uses [SEP-53](https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0053.md) standard format:
```
message = network_hash + contract_id + function_name + args + ledger_expiry
```

## Usage

1. **Connect Wallet**: Click "Connect" button
2. **Start NFC Server**: Run `bun run nfc-server` in a terminal
3. **Check NFC Status**: Should show "Connected" 
4. **Place Chip**: Position Infineon NFC chip on uTrust 4701F reader
5. **Mint NFT**: Click "Mint NFT with Chip"
6. **Sign**: Chip signs challenge
7. **Approve**: Approve transaction in wallet
8. **Success**: Token ID = chip's public key

## Troubleshooting

### Desktop Issues

**NFC Server Won't Start**
- Ensure `ws` package installed: `cd nfc-server && bun install ws`
- Check port 8080 is free: `lsof -i :8080`
- Verify blocksec2go works: `uv run --with blocksec2go blocksec2go get_card_info`

**Reader Not Detected**
- Check USB connection
- Verify uTrust 4701F is recognized by system
- Test with: `uv run --with blocksec2go blocksec2go get_card_info`

**Chip Not Detected**
- Place chip flat on reader surface
- Ensure chip is Infineon SECORA Blockchain compatible
- Check NFC server console for "✓ Chip detected!"

### Common Errors

**"ECDSA signature 's' part is not normalized"**
- Fixed in code: NFC server normalizes signatures automatically
- If still occurs, signature parsing may have failed

**"No signature needed"**
- Contract doesn't modify state yet
- Using `force: true` to test signature recovery

**Public Key Mismatch**
- Recovery ID defaults to 1 for Infineon chips
- If mismatch persists, verify chip is Infineon SECORA Blockchain compatible
- Frontend and contract must hash the same message

## Configuration

### NFC Server Port

Edit `nfc-server/index.js`:
```javascript
const PORT = 8080; // Change port here
```

### Recovery ID

Recovery ID is set to 1 by default for Infineon SECORA chips. This is configured in the NFC server and should not need adjustment.

## Technical Details

### Contract Function
```rust
fn mint(
    e: &Env,
    to: Address,
    message: Bytes,        // SEP-53 message (variable length)
    signature: BytesN<64>, // ECDSA signature (r + s)
    recovery_id: u32,      // 0-3
) -> BytesN<65> {
    let hash = e.crypto().sha256(&message);
    e.crypto().secp256k1_recover(&hash, &signature, recovery_id)
}
```

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

## Security

- ✅ Private keys never leave the chip
- ✅ SEP-53 standard authentication
- ✅ Ledger-based expiry prevents replay attacks
- ✅ Signature normalization ensures compatibility
- ✅ Hardware-secured cryptographic operations

## Development

### Project Structure
```
stellar-merch-shop/
├── nfc-server/          # WebSocket server for Desktop USB readers
│   ├── index.js        # blocksec2go wrapper
│   └── package.json
├── contracts/
│   └── stellar-merch-shop/
│       └── src/
│           └── contract.rs  # Mint function with secp256k1_recover
├── src/
│   ├── components/
│   │   ├── NFCStatus.tsx       # Connection status
│   │   └── NFCMintProduct.tsx  # Main mint UI
│   ├── hooks/
│   │   └── useNFC.ts           # NFC state management
│   ├── util/
│   │   ├── nfcClient.ts        # WebSocket client (Desktop)
│   │   └── crypto.ts           # SEP-53 + signature formatting
│   └── contracts/
│       └── stellar_merch_shop.ts  # Contract client wrapper
└── packages/
    └── stellar_merch_shop/  # Auto-generated by scaffold
```

### Adding Storage to Contract

The current contract only recovers the public key. To make it functional:

```rust
fn mint(...) -> BytesN<65> {
    let hash = e.crypto().sha256(&message);
    let public_key = e.crypto().secp256k1_recover(&hash, &signature, recovery_id);
    
    // Add storage:
    // 1. Store token ownership
    e.storage().persistent().set(&NFTStorageKey::Owner(token_id), &to);
    
    // 2. Update balance
    let balance = e.storage().persistent().get(&NFTStorageKey::Balance(&to)).unwrap_or(0);
    e.storage().persistent().set(&NFTStorageKey::Balance(&to), &(balance + 1));
    
    // 3. Emit mint event
    e.events().publish(("mint",), (to.clone(), token_id));
    
    public_key
}
```

## Support

- Check console logs in browser (F12)
- Check NFC server terminal for blocksec2go output
- Verify chip with: `uv run --with blocksec2go blocksec2go get_card_info`
- See DEVELOPMENT.md for architecture details

## License

MIT
