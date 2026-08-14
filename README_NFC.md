# NFC Chip Integration Guide

Using Infineon SECORA and NXP MIFARE DUOX chips with the Stellar contracts: mint, claim and transfer NFTs with hardware-backed signatures.

## Related repositories

| Repo | Radicle | Purpose |
|------|---------|---------|
| **chimpdao-nfc-bridge** | [z2CDTfv…](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az2CDTfvUguLG3UboK46HyYxoxg1og) | Node.js PC/SC WebSocket bridge + `@chimpdao/nfc-client` |
| **chimpdao-terminal** | [z4Y793T…](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az4Y793TkQB4X4Uz4CRdEMUHxakZKt) | Merchant tap-to-pay (XRPL + Stellar UI) |
| **chimpdao-contracts** | this repo | Soroban contracts |

```bash
git clone https://radicle.consulting-manao.com/z2CDTfvUguLG3UboK46HyYxoxg1og.git chimpdao-nfc-bridge
```

## Prerequisites

- **Hardware**: Infineon SECORA chip + Identiv/uTrust USB reader
- **Software**: Node.js ≥ 22 for the bridge; Bun for the terminal
- **Wallet**: Freighter or compatible Stellar wallet

## Running

```bash
# Terminal 1: NFC bridge (Node only — not Bun)
cd chimpdao-nfc-bridge
npm install && npm start

# Terminal 2: the POS
cd ../chimpdao-terminal
bun install && bun run dev
```

Card setup — purse, mint, assign, tag link — is **Set up a card** in the terminal.

If the chip was already on the reader when the bridge started, **lift and retap**.

## Architecture

```
Browser ← WebSocket → chimpdao-nfc-bridge ← nfc-pcsc → USB Reader ← NFC → Chip
```

Protocol: `status` | `read-pubkey` | `sign` | `read-ndef` | `write-ndef` | `generate-key` | `fetch-key`

Full spec: [chimpdao-nfc-bridge/docs/PROTOCOL.md](https://radicle.consulting-manao.com/z2CDTfvUguLG3UboK46HyYxoxg1og.git) (clone the bridge repo).

### Stellar flow

The client no longer builds its own message — the digest the chip signs is derived from
the call itself, so a signature cannot be moved to a different one.

**Pocket (the chip is the account):**

1. Read the chip public key (65-byte SEC1)
2. Build the operation (e.g. a SAC `transfer`) and simulate it
3. Take the host's authorization payload from the prepared auth entry
4. Chip signs that 32-byte payload
5. Recover the recovery id (`@noble/secp256k1`), inject `ChipAuth` as the credential
6. Re-simulate in `enforce` mode so the footprint covers `__check_auth`, then submit

**nfc-nft (the chip is a presence proof beside a wallet):**

1. Read the chip public key and the chip's nonce on the contract
2. Build `call_digest(domain, contract, fn, args, nonce)` — see `src/chain/chip-auth.ts`
3. Chip signs it; submit alongside the wallet's own authorization

A cross-client test pins the TypeScript `callDigest` against the Rust implementation; if
they ever diverge every attestation is rejected on-chain with an opaque contract error.

### Merchant terminal (XRPL)

```bash
git clone https://radicle.consulting-manao.com/z4Y793TkQB4X4Uz4CRdEMUHxakZKt.git chimpdao-terminal
```

## Signature format

- **From chip**: DER-encoded ECDSA
- **From bridge**: `r` + `s` as 32-byte hex (low-S)
- **Terminal**: `chipAuthForDigest()` in `src/chain/chip-auth.ts`

Contract tests cover digest construction and rejection paths only; a valid signature is
proven on live hardware, not simulated. `cargo test -p chimpdao-chip-auth` pins the
digest the terminal must reproduce.
