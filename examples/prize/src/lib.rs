//! # ChimpDAO Prize (example)
//!
//! Reference app: how to lean on the NFT registry as the auth layer.
//!
//! Presence pattern (used here):
//! 1. Bind the `nfc-nft` contract at construction, never as a call argument.
//! 2. Digest *your* call under your own domain — [`chimpdao_chip_auth::call_digest`] —
//!    and keep your own nonce.
//! 3. Cross-call `nfc.verify_for_card(public_key, digest, auth)` — no crypto, no curve
//!    mapping in your contract.
//!
//! Authority pattern (when account control is enough): the NFT is soulbound to the
//! card, so `nfc.owner_of(token_id) == redeemer` + `redeemer.require_auth()` proves
//! card authority in two lines — no attestation at all.
//!
//! Not part of the core protocol — see `examples/prize/README.md`.

#![no_std]

use soroban_sdk::{Address, Bytes, BytesN, Env, contract, contractclient, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Prize");

// The registry speaks these types directly — no need to generate a client from its wasm.
pub use chimpdao_chip_auth::{ChipAuth, Secp256k1Auth};

/// The slice of `nfc-nft` an integrator needs: verify a chip, then resolve its token.
/// Declared rather than imported from built wasm, so this example compiles on its own.
#[contractclient(name = "NfcClient")]
#[allow(dead_code)]
trait NfcRegistry {
    fn verify_for_card(e: Env, public_key: BytesN<65>, digest: Bytes, auth: ChipAuth) -> bool;
    fn public_key(e: Env, token_id: u32) -> BytesN<65>;
    fn token_id(e: Env, public_key: BytesN<65>) -> u32;
    fn owner_of(e: Env, token_id: u32) -> Address;
}

mod contract;
mod errors;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct Prize;

pub trait PrizeTrait {
    /// * `admin` - Address allowed to upgrade the contract.
    /// * `token` - Token contract address (e.g. the XLM Stellar Asset Contract).
    /// * `nfc_contract` - The one NFC-NFT contract this prize trusts. Bound here, not
    ///   passed per call: a caller-supplied address would let anyone substitute a
    ///   contract that reports them as the owner of any chip and drain every vault.
    fn __constructor(e: &Env, admin: Address, token: Address, nfc_contract: Address);

    /// Upgrade the contract to a new WASM build. Admin only.
    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// The NFC-NFT contract bound at construction.
    fn nfc_contract(e: &Env) -> Address;

    /// Lock `amount` for the chip behind `token_id`.
    ///
    /// # Events
    ///
    /// * topics - `["Deposit", token_id]`
    fn deposit(e: &Env, from: Address, amount: i128, token_id: u32);

    /// Redeem the locked amount for a chip.
    ///
    /// The chip attests to `("redeem", [redeemer], nonce)` under this contract's own
    /// domain, so the attestation cannot be replayed against `nfc-nft` or any other
    /// integrator, nor redirected to a different redeemer.
    ///
    /// # Panics
    ///
    /// * If `redeemer` does not authorize.
    /// * If the chip attestation is invalid or the nonce was already used.
    /// * If `redeemer` is not the current owner of the NFT for this chip.
    /// * If there is nothing locked for this chip.
    fn redeem(e: &Env, redeemer: Address, auth: ChipAuth, public_key: BytesN<65>, nonce: u32);

    /// Locked amount for a chip public key, or 0.
    fn get_redeemable(e: &Env, chip_public_key: BytesN<65>) -> i128;

    /// Last consumed attestation nonce for a chip.
    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32;
}
