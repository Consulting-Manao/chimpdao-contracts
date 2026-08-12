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
Chi//mp provides one: three Soroban smart contracts that treat an on-chip
ECDSA signature as the authoritative credential for minting, claiming, and
transferring an NFT, plus a worked-example application that locks tokens
under a chip's public key and pays them out only to the current NFT owner.

## Repository layout

| Path                                            | Purpose                                                                             |
|-------------------------------------------------|-------------------------------------------------------------------------------------|
| [`contracts/nfc-nft/`](contracts/nfc-nft)       | SEP-50 NFT contract; every mutator routes through `verify_chip_signature`.          |
| [`contracts/collection/`](contracts/collection) | Factory that deploys NFC-NFT contracts and indexes ownership across them.           |
| [`contracts/prize/`](contracts/prize)           | Reference downstream application: per-chip token vault redeemable by the NFT owner. |
| [`contracts/smart-account/`](contracts/smart-account) | **Pocket** — per-chip ChipAuth account (spend, Earn link, positions). |
| [`contracts/smart-account-factory/`](contracts/smart-account-factory) | Deploys Pocket accounts (`salt = sha256(pubkey)`). |
| [`contracts/chip-verifier/`](contracts/chip-verifier) | OZ Verifier for Earn (Nido External); Infineon k1 + DUOX r1 IntAuth. |
| [`dapp/`](dapp)                                 | TypeScript desktop administration interface (Vite + React + Stellar SDK).           |
| [`Makefile`](Makefile)                          | Build, test, deploy targets.                                                        |

### Pocket / Earn (terminal)

Merchant POS is **chimpdao-terminal**. Naming: **Pocket** = ChipAuth smart-account; **Earn** = Nido C with `External(chip-verifier, pubkey)`.

```bash
make contract_build
make contract_test
make contract_deploy_chip_verifier
make contract_deploy_factory   # requires collection_$(network)_id
```

Factory constructor: `--admin` + `--collection_contract`. Pocket wasm hash is written next to the factory id.

Auth: Pocket keeps local `message‖signer‖nonce` + monotonic nonce. `chip-verifier` is intentionally **stateless** (OZ crypto oracle); Earn replay is Soroban auth + OZ rule-id digest.

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
| `prize` (reference)           | testnet | [`CBVSY77ZRLZQ7OR62MIERRL6VNZMFZOVSCASS77J4NAR5VMRLXTVWE3F`](https://stellar.expert/explorer/testnet/contract/CBVSY77ZRLZQ7OR62MIERRL6VNZMFZOVSCASS77J4NAR5VMRLXTVWE3F) |

All deployment IDs are committed under
[`.config/stellar/`](.config/stellar) and are kept in sync with the `Makefile`
targets.
