# Chi//mp: physical-backed tokens on Stellar

Chi//mp links a Stellar non-fungible token (NFT) to a single physical object
through an NFC chip embedded in the object. The chip generates its own
elliptic-curve key pair in tamper-resistant silicon, the private key never
leaves the chip, and an ECDSA signature from the chip authorises every
state-changing call on the NFT. The repository serves both as a deployed
Stellar mainnet system and as a reproducible reference implementation for
studying hardware-anchored authorisation on a non-EVM ledger.

## What this is

Production systems that tie a physical object to a digital identifier through
an NFC chip either keep a chip identifier in a custodial database (vulnerable
to cloning of identifier-only tags) or live on Ethereum-compatible chains
(ERC-5791 / Chiru Labs PBT). Stellar previously had no open-source equivalent.
Chi//mp provides one: Soroban contracts that treat an on-chip ECDSA signature
as the authoritative credential for NFTs and per-chip Pocket accounts, plus
an example app that locks tokens under a chip public key.

## Docs

| Doc | Content |
|-----|---------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Crate map, deploy/lifecycle diagrams, storage |
| [`docs/AUTH.md`](docs/AUTH.md) | ChipAuth digest, replay, Pocket vs Earn |

## Repository layout

| Path                                            | Purpose                                                                             |
|-------------------------------------------------|-------------------------------------------------------------------------------------|
| [`contracts/nfc-nft/`](contracts/nfc-nft)       | SEP-50 NFT contract; every mutator requires a chip attestation for that exact call. |
| [`contracts/collection/`](contracts/collection) | Factory that deploys NFC-NFT contracts and indexes ownership across them.           |
| [`contracts/smart-account/`](contracts/smart-account) | **Pocket** — per-card purse; a Soroban custom account keyed by the chip. |
| [`contracts/smart-account-factory/`](contracts/smart-account-factory) | Deploys Pocket accounts (`salt = sha256(pubkey)`). |
| [`contracts/chip-verifier/`](contracts/chip-verifier) | OZ Verifier for Earn (Nido External); Infineon k1 + DUOX r1 IntAuth. |
| [`examples/prize/`](examples/prize)             | Example app: per-chip token vault (not core protocol).                              |
| [`Makefile`](Makefile)                          | Build, test, deploy and admin targets.                                              |

Administration lives in **chimpdao-terminal** (card setup, mint, claim) and in the
Makefile (deploy, `contract_clawback`). The repo previously carried a second React admin
`dapp/`; it was superseded by the terminal and is removed.

### Accounts, purses and cards

The durable account is a **Nido** (OpenZeppelin smart account). Cards are `External`
signers on it, which is what makes a card replaceable: losing one is `remove_signer` +
`add_signer`, not losing the balance.

**Pocket** is a small per-card purse for fast taps, deliberately loss-tolerant. It stores
the owning Nido account so that account can `sweep` a lost card's float. **Earn** is the
Nido account itself, reached through `External(chip-verifier, pubkey)`.

```bash
make contract_build            # builds in dependency order
make contract_test
make contract_deploy_chip_verifier
make contract_deploy_factory   # requires collection_$(network)_id
```

The factory needs both a collection pointer and an approved Pocket wasm hash before it
can deploy accounts; it no longer accepts a wasm hash per call.

Auth: Pocket implements `CustomAccountInterface`, so the **host** binds each signature to
the exact call — there is no Pocket `transfer` entry point and no app-level nonce.
`chip-verifier` is intentionally **stateless** (an OZ crypto oracle); Earn replay is
Soroban auth plus the OZ rule-id digest. Details in [`docs/AUTH.md`](docs/AUTH.md).

The NFC hardware bridge lives in **[chimpdao-nfc-bridge](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az2CDTfvUguLG3UboK46HyYxoxg1og)**; the merchant POS in **[chimpdao-terminal](https://radicle.network/nodes/radicle.consulting-manao.com/rad%3Az4Y793TkQB4X4Uz4CRdEMUHxakZKt)** (Radicle repos under consulting-manao).

```bash
git clone https://radicle.consulting-manao.com/z2CDTfvUguLG3UboK46HyYxoxg1og.git chimpdao-nfc-bridge
git clone https://radicle.consulting-manao.com/z4Y793TkQB4X4Uz4CRdEMUHxakZKt.git chimpdao-terminal
```

The full chip-integration guide is in [`README_NFC.md`](README_NFC.md). The
mobile tap-to-claim flow lives in a companion iOS application.

## Mainnet deployment

| Contract                      | Network | Address                                                                                                                                                                 |
|-------------------------------|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `collection`                  | mainnet | [`CCWQBP7UOTSHMNEVE2P2DCLNI37CFA4WNPMUBNES5BH7QEEEUBXL7Y5Z`](https://stellar.expert/explorer/public/contract/CCWQBP7UOTSHMNEVE2P2DCLNI37CFA4WNPMUBNES5BH7QEEEUBXL7Y5Z)  |
| `nfc-nft` (collection `chi1`) | mainnet | [`CCTPN4LRCNJBLC3VVEYET7MRLQHSAAXTQG4YBG7W3HORHZFHJIIQ7BLO`](https://stellar.expert/explorer/public/contract/CCTPN4LRCNJBLC3VVEYET7MRLQHSAAXTQG4YBG7W3HORHZFHJIIQ7BLO)  |
| `prize` (example)             | testnet | [`CBVSY77ZRLZQ7OR62MIERRL6VNZMFZOVSCASS77J4NAR5VMRLXTVWE3F`](https://stellar.expert/explorer/testnet/contract/CBVSY77ZRLZQ7OR62MIERRL6VNZMFZOVSCASS77J4NAR5VMRLXTVWE3F) |

All deployment IDs are committed under
[`.config/stellar/`](.config/stellar) and are kept in sync with the `Makefile`
targets.
