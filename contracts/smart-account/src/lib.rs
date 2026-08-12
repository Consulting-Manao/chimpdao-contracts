//! ChimpDAO Pocket smart account
//!
//! Per-chip ChipAuth account: spend, Earn link, positions, collection pointer.
#![no_std]

use soroban_sdk::{contract, contractmeta, Address, Bytes, BytesN, Env, Symbol, Vec};

contractmeta!(key = "Description", val = "ChimpDAO Pocket smart account");

mod contract;
mod errors;
mod events;
#[cfg(test)]
mod test;
mod types;

#[contract]
pub struct SmartAccount;

pub trait SmartAccountTrait {
    /// * `collection_contract` - NFT collection index for Card identity reads.
    /// * `chip` - Bound SEC1 pubkey (Instance storage; not a call arg on gated fns).
    fn __constructor(
        e: &Env,
        admin: Address,
        collection_contract: Address,
        chip: BytesN<65>,
        curve: types::Curve,
    );

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    fn balance(e: &Env, token: Address) -> i128;

    /// Pay `amount` of SEP-41 `token` from this contract to `to`, authorized by the bound chip.
    ///
    /// `from` must be this contract. Digest = `sha256(message ‖ signer_xdr ‖ nonce_xdr)`.
    fn transfer(
        e: &Env,
        token: Address,
        from: Address,
        to: Address,
        amount: i128,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    );

    fn get_nonce(e: &Env) -> u32;

    /// NFT collection contract stored at deploy (Card identity).
    fn collection(e: &Env) -> Address;

    /// Admin sets/updates collection pointer (migrate upgraded Pocket accounts).
    fn set_collection(e: &Env, collection_contract: Address);

    /// Collectibles for `from` via the linked collection index.
    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)>;

    fn get_earn(e: &Env) -> Option<types::EarnLink>;

    fn set_earn(
        e: &Env,
        link: types::EarnLink,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    );

    fn clear_earn(e: &Env, message: Bytes, auth: types::ChipAuth, nonce: u32);

    fn get_positions(e: &Env) -> Vec<types::Position>;

    fn upsert_position(
        e: &Env,
        position: types::Position,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    );

    fn clear_position(
        e: &Env,
        strategy_id: Symbol,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    );
}
