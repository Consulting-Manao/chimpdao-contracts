//! # ChimpDAO Prize
//!
//! Lock XLM (or a configured token) per chip and redeem with chip signature proof.
//! The contract resolves campaign (nfc_contract + token_id) to a globally unique chip
//! public key at lock time; redemptions are keyed by that public key. Only the current
//! owner of the NFT for the chip in the given NFC contract can redeem.

#![no_std]

use soroban_sdk::{Address, Bytes, BytesN, Env, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Prize");

mod nfc_contract {
    soroban_sdk::contractimport!(file = "../nfc_nft.wasm");
}

mod contract;
mod errors;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct Prize;

pub trait PrizeTrait {
    /// Initialize the prize contract.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `admin` - Address allowed to upgrade the contract.
    /// * `token` - Token contract address (e.g. XLM Stellar Asset Contract).
    fn __constructor(e: &Env, admin: Address, token: Address);

    /// Upgrade the contract to a new WASM build. Admin only.
    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// Deposit tokens for a specific prize campaign.
    ///
    /// Resolves `(nfc_contract, token_id)` to the chip public key via a cross-call to
    /// the NFC contract's `public_key(token_id)`. The locked amount is stored under
    /// that chip public key; additional locks for the same chip add to the balance.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `from` - Address locking the funds (must authorize the transfer).
    /// * `amount` - Amount to lock.
    /// * `nfc_contract` - NFC-NFT contract address for the campaign.
    /// * `token_id` - Token ID in that contract (maps to a chip public key).
    ///
    /// # Panics
    ///
    /// * If `from` does not authorize the transfer.
    /// * If `token_id` does not exist in `nfc_contract`.
    ///
    /// # Events
    ///
    /// * topics - `["Lock", nfc_contract: Address]`
    /// * data - `Lock { token_id, amount, from }`
    fn deposit(e: &Env, from: Address, amount: i128, nfc_contract: Address, token_id: u32);

    /// Redeem locked token for a chip.
    ///
    /// Verifies the chip signature via the given NFC contract, ensures the redeemer
    /// is the current owner of the NFT for that chip, then transfers the locked amount
    /// to the redeemer and sets the lock balance to zero.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `redeemer` - Address redeeming (must authorize; must be NFT owner for the chip).
    /// * `nfc_contract` - NFC-NFT contract used for signature verification and owner check.
    /// * `message` - Message that was signed (without signer and nonce).
    /// * `signature` - 64-byte ECDSA signature from the chip.
    /// * `recovery_id` - Recovery ID (0–3) for signature recovery.
    /// * `public_key` - Chip public key (uncompressed SEC1, 65 bytes).
    /// * `nonce` - Nonce used in the signed payload.
    ///
    /// # Panics
    ///
    /// * If the redeemer does not authorize.
    /// * If the chip signature is invalid (via NFC contract).
    /// * If the redeemer is not the owner of the NFT for this chip ([`errors::PrizeError::NotChipOwner`]).
    /// * If there is no locked amount for this chip ([`errors::PrizeError::NoLockForChip`]).
    ///
    /// # Events
    ///
    /// * topics - `["Redeem", nfc_contract: Address]`
    /// * data - `Redeem { token_id, amount, redeemer }`
    #[allow(clippy::too_many_arguments)]
    fn redeem(
        e: &Env,
        redeemer: Address,
        nfc_contract: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    );

    /// Return the locked amount for the given chip public key.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `chip_public_key` - Chip public key (uncompressed SEC1, 65 bytes).
    ///
    /// # Returns
    ///
    /// The locked amount, or 0 if none.
    fn get_redeemable(e: &Env, chip_public_key: BytesN<65>) -> i128;
}
