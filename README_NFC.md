# NFC Chip Integration Guide

Complete guide for using Infineon SECORA Blockchain NFC chips with the Stellar dapp. Mint, claim, and transfer NFTs with hardware-secured signatures.

## Related repositories

| Repo | Radicle | Purpose |
|------|---------|---------|
| **chimpdao-nfc-bridge** | [z2CDTfv…](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az2CDTfvUguLG3UboK46HyYxoxg1og) | Node.js PC/SC WebSocket bridge + `@chimpdao/nfc-client` |
| **chimpdao-terminal** | [z4Y793T…](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az4Y793TkQB4X4Uz4CRdEMUHxakZKt) | Merchant tap-to-pay (XRPL + Stellar UI) |
| **chimpdao-contracts** | this repo | Soroban contracts + admin dapp |

```bash
git clone https://radicle.consulting-manao.com/z2CDTfvUguLG3UboK46HyYxoxg1og.git chimpdao-nfc-bridge
```

## Prerequisites

- **Hardware**: Infineon SECORA chip + Identiv/uTrust USB reader
- **Software**: Node.js ≥ 22 for the bridge; Bun for the dapp
- **Wallet**: Freighter or compatible Stellar wallet

## Running

```bash
# Terminal 1: NFC bridge (Node only — not Bun)
cd chimpdao-nfc-bridge
npm install && npm start

# Terminal 2: Stellar dapp
cd dapp
bun install && bun run dev

# Or from dapp (bridge must be cloned as sibling):
bun run dev:with-nfc
```

If the chip was already on the reader when the bridge started, **lift and retap**.

## Architecture

```
Browser ← WebSocket → chimpdao-nfc-bridge ← nfc-pcsc → USB Reader ← NFC → Chip
```

Protocol: `status` | `read-pubkey` | `sign` | `read-ndef` | `write-ndef` | `generate-key` | `fetch-key`

Full spec: [chimpdao-nfc-bridge/docs/PROTOCOL.md](https://radicle.consulting-manao.com/z2CDTfvUguLG3UboK46HyYxoxg1og.git) (clone the bridge repo).

### Stellar flow

1. Read chip public key (65-byte SEC1)
2. Fetch nonce for SEP-53
3. Build SEP-53 auth message
4. Hash with SHA-256
5. Chip signs the 32-byte digest
6. Client recovers recovery ID (`@noble/secp256k1`)
7. Submit to Soroban contract with `r||s` + recovery ID

### Merchant terminal (XRPL)

```bash
git clone https://radicle.consulting-manao.com/z4Y793TkQB4X4Uz4CRdEMUHxakZKt.git chimpdao-terminal
```

## Signature format

- **From chip**: DER-encoded ECDSA
- **From bridge**: `r` + `s` as 32-byte hex (low-S)
- **Stellar dapp**: `formatSignatureForSoroban()` in `dapp/src/util/crypto.ts`

## Regenerating NFC test signatures

See [dapp/scripts/REGENERATE_NFC_TEST_SIGS.md](dapp/scripts/REGENERATE_NFC_TEST_SIGS.md).
