//! ChimpDAO Pocket smart account
//!
//! Per-card spending purse. The bound chip is the account key: Pocket implements
//! `CustomAccountInterface`, so every call it authorizes is bound by the host to the
//! exact contract, function, arguments, network, nonce and expiration ledger.
//!
//! The purse is deliberately loss-tolerant — the durable account is the user's Nido
//! (OZ smart account), stored here as `Owner`, which can `sweep` a lost card's float.
#![no_std]

use soroban_sdk::{Address, BytesN, Env, Symbol, Vec, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Pocket smart account");

mod auth;
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
    /// * `chip` - Bound SEC1 pubkey (Instance storage; never a call argument).
    /// * `owner` - Durable Nido account that can recover this purse.
    /// * `upgrade_policy` - What the holder chose at onboarding.
    fn __constructor(
        e: &Env,
        collection_contract: Address,
        chip: BytesN<65>,
        curve: types::Curve,
        owner: Address,
        upgrade_policy: types::UpgradePolicy,
    );

    /// Replace WASM. Authorized by the chip via `__check_auth`, which binds `wasm_hash`.
    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// What the holder agreed to at onboarding. Drives who gets an upgrade pushed and
    /// who gets a notification.
    fn upgrade_policy(e: &Env) -> types::UpgradePolicy;

    /// Holder changes their mind. Chip-authorized — this is a consent decision.
    fn set_upgrade_policy(e: &Env, policy: types::UpgradePolicy);

    fn balance(e: &Env, token: Address) -> i128;

    /// NFT collection contract stored at deploy (Card identity).
    fn collection(e: &Env) -> Address;

    /// Chip sets/updates collection pointer.
    fn set_collection(e: &Env, collection_contract: Address);

    /// Collectibles for `from` via the linked collection index.
    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)>;

    /// Durable Nido account behind this purse.
    fn owner(e: &Env) -> Address;

    /// Recover the purse float to `to`. Authorized by `owner`, not the chip — this is
    /// the lost-card path, so it must work when the chip is gone.
    fn sweep(e: &Env, token: Address, to: Address);

    fn get_earn(e: &Env) -> Option<types::EarnLink>;

    fn set_earn(e: &Env, link: types::EarnLink);

    fn clear_earn(e: &Env);

    fn get_positions(e: &Env) -> Vec<types::Position>;

    fn upsert_position(e: &Env, position: types::Position);

    fn clear_position(e: &Env, strategy_id: Symbol);
}
