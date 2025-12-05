# Development Guide

Technical documentation for the NFC chip integration implementation.

## Architecture

### Dual-Mode Support

The app automatically detects and uses the appropriate NFC interface:

**Desktop Mode** (WebSocket):
```
React App ← WebSocket ← NFC Server ← blocksec2go CLI ← PC/SC ← USB Reader ← Chip
```

**Android Mode** (Web NFC):
```
React App ← Web NFC API ← Phone NFC Hardware ← Chip
```

### Why Two Modes?

- **Desktop**: Browsers can't access USB devices directly for security. WebSocket bridge provides PC/SC access.
- **Android**: Web NFC API available in Chrome/Edge 89+, direct chip communication.
- **iOS**: Not supported (Web NFC not available)

## Implementation Details

### Contract (Rust/Soroban)

**Key Insight**: `Hash<32>` type can only be constructed via secure cryptographic functions in Soroban.

```rust
fn mint(e: &Env, to: Address, message: Bytes, signature: BytesN<64>, recovery_id: u32) -> BytesN<65> {
    // Must hash in contract to get Hash<32>
    let message_hash = e.crypto().sha256(&message);
    
    // secp256k1_recover requires &Hash<32>, not &BytesN<32>
    e.crypto().secp256k1_recover(&message_hash, &signature, recovery_id)
}
```

**Why**:
- `Hash::from_bytes()` is test-only (`#[cfg(test)]`)
- Top-level functions can only use `BytesN<32>`, not `Hash<32>`
- `sha256()` returns `Hash<32>` which `secp256k1_recover` requires

### Frontend (TypeScript/React)

**SEP-53 Message Creation** (`src/util/crypto.ts`):
```typescript
// Creates standard auth message
message = concat(
  sha256(networkPassphrase),
  contractId,
  functionName,
  JSON.stringify(args),
  validUntilLedger (4 bytes, big endian)
)

messageHash = sha256(message)
```

**NFC Signing Flow**:
1. Create SEP-53 message
2. Hash with SHA-256
3. Send 32-byte hash to chip
4. Chip signs hash directly
5. Parse DER signature → normalize s value
6. Send original message + signature to contract

### NFC Server (Node.js)

Uses `blocksec2go` Python CLI via `child_process`:

**Commands**:
```bash
# Check chip presence
blocksec2go get_card_info

# Read public key (key index 1)
blocksec2go get_key_info 1

# Sign 32-byte hash (key index 1)
blocksec2go generate_signature 1 <hex>
```

**DER Signature Parsing**:
```
DER Format: 30 [len] 02 [r-len] [r] 02 [s-len] [s]
```

**Signature Normalization**:
Stellar/Soroban requires s < curve_order/2:
```javascript
if (s > HALF_CURVE_ORDER) {
  s = CURVE_ORDER - s
}
```

**Recovery ID Detection**:
- blocksec2go doesn't return v explicitly
- Automatically determined by trying all recovery IDs (0-3)
- Compares recovered public key with known chip public key
- Uses `@noble/secp256k1` for client-side recovery
- Ensures correct recovery ID without manual configuration

## Key Learnings

### Issue 1: Hash Type Constraints
**Problem**: Can't use `Hash<32>` in contract function signature  
**Solution**: Use `BytesN<32>`, convert with `.into()` or hash internally

### Issue 2: Native Bindings
**Problem**: `nfc-pcsc` requires node-gyp compilation  
**Solution**: Use `blocksec2go` CLI via child_process (no native bindings)

### Issue 3: Signature Normalization
**Problem**: Chip produces "high s" values rejected by Soroban  
**Solution**: Normalize s to low form (s < n/2) in NFC server

### Issue 4: Recovery ID
**Problem**: blocksec2go doesn't return v value  
**Solution**: Automatically detect by trying all recovery IDs (0-3) and matching recovered public key with chip's known public key using `@noble/secp256k1`

### Issue 5: Double Hashing
**Problem**: Chip signs hash, but contract also needs to hash  
**Solution**: Chip signs `sha256(message)`, contract receives `message` and computes `sha256(message)`

## Data Flow

```
1. Frontend: Fetch current ledger from Horizon API
   ↓
2. Frontend: message = SEP-53(message, ledger) (variable length)
   ↓
3. Frontend: hash = sha256(message) (32 bytes)
   ↓
4. NFC Chip: signature = sign(hash, privateKey)
   ↓
5. Frontend: Try recovery IDs 0-3, match recovered key with chip's public key
   ↓
6. Contract: receives message + signature + detected recovery_id
   ↓
7. Contract: hash = sha256(message)
   ↓
8. Contract: publicKey = secp256k1_recover(hash, signature, recovery_id)
   ↓
9. publicKey = token ID
```

## Type Mappings

| Contract (Rust) | Frontend (TS) | Notes |
|---|---|---|
| `Bytes` | `Buffer` | Variable-length bytes |
| `BytesN<32>` | `Uint8Array(32)` | Fixed 32 bytes |
| `BytesN<64>` | `Uint8Array(64)` | Fixed 64 bytes (r+s) |
| `BytesN<65>` | `Uint8Array(65)` | Public key (uncompressed) |
| `u32` | `number` | Recovery ID (0-3) |
| `Address` | `string` | Stellar address |

## Testing

### Unit Tests
Run tests for crypto utilities:
```bash
# Add tests for signature normalization, SEP-53 creation
```

### Integration Tests
1. Mock NFC client responses
2. Test SEP-53 message creation
3. Verify signature formatting
4. Test recovery ID handling

### E2E Tests
1. Start both servers
2. Connect wallet
3. Place chip on reader
4. Click mint
5. Verify recovered public key matches chip

## Production Deployment

### Backend (NFC Server)
- Deploy on server with USB reader attached
- Use WSS (not WS) for secure WebSocket
- Add authentication if exposing publicly
- Consider rate limiting

### Frontend
```bash
bun run build
```
Deploy `dist/` folder

### Contract
Deploy to mainnet:
```bash
stellar contract deploy --wasm target/wasm32v1-none/release/stellar_merch_shop.wasm
```

## Performance

- **NFC Read**: ~500ms
- **Signature**: ~1-2s (chip operation)
- **Contract Call**: ~5s (network + consensus)
- **Total**: ~7-10s per mint

## Security Considerations

1. **Private Key Security**: Never leaves chip hardware
2. **Replay Prevention**: SEP-53 ledger expiry
3. **Signature Malleability**: s-value normalized to low form
4. **Network Security**: WebSocket local-only in dev
5. **Browser Security**: Web NFC requires HTTPS in production

## Future Improvements

1. **Web NFC APDU**: Full APDU-over-NDEF implementation (currently limited by browser API)
2. **Multi-Signature**: Support multiple chips for authentication
3. **Token Storage**: Complete NFT storage implementation in contract
4. **Events**: Emit proper NFT mint/transfer events
5. **Performance**: Cache ledger numbers to reduce API calls

## Dependencies

### Frontend
- `@stellar/stellar-sdk` - Stellar SDK
- `@stellar/design-system` - UI components
- `react` - UI framework

### NFC Server
- `ws` - WebSocket server
- `blocksec2go` - Infineon chip CLI (Python, via uv)

### Contract
- `soroban-sdk` - Soroban smart contract SDK

## References

- [Soroban SDK Docs](https://docs.rs/soroban-sdk)
- [Infineon Blockchain Security 2Go](https://github.com/Infineon/Blockchain)
- [SEP-53 Specification](https://github.com/stellar/stellar-protocol/blob/master/ecosystem/sep-0053.md)
- [secp256k1 Curve](https://en.bitcoin.it/wiki/Secp256k1)

