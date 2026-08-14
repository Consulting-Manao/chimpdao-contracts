//! # ChimpDAO Prize (example)
//!
//! Reference app: how to require a chip presence attestation in your own contract.
//!
//! 1. Bind the `nfc-nft` contract at construction, never as a call argument.
//! 2. Read the chip's `public_key` / `curve` from it.
//! 3. Digest *your* call under your own domain — [`chimpdao_chip_auth::call_digest`].
//! 4. [`chimpdao_chip_auth::verify_chip_auth`], then bump your own nonce.
//!
//! Step 3 is the point: a signature over an opaque blob proves the card met a reader at
//! some time, not that the holder agreed to this call.
//!
//! Not part of the core protocol — see `examples/prize/README.md`.

#![no_std]

use soroban_sdk::{Address, BytesN, Env, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Prize");

mod nfc_contract {
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/nfc_nft.wasm");
}

pub use chimpdao_chip_auth::{ChipAuth, Curve, Secp256k1Auth, Secp256r1Auth};

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
