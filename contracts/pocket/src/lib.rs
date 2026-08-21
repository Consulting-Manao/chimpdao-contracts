//! Per-card spending purse: the chip is the key and this contract is the account shell
//! around it. Pocket implements `CustomAccountInterface`, so every call it authorizes is
//! bound by the host to the exact contract, function, arguments, network, nonce and
//! expiration ledger. Signature checking is linked from `chimpdao-chip-auth` against the
//! key and curve stored at construction — see `auth.rs`.
//!
//! It holds the card's spendable float **and its DeFi positions**: `__check_auth` applies
//! no per-context policy, so the purse can authorize a lending-pool call as readily as a
//! token transfer. Positions therefore travel with the card when it changes hands.
//!
//! Deliberately loss-tolerant — the durable account is the holder's Chimp account, stored as
//! `Owner`, which can `sweep` a lost card's float and receives the purse on handover.
#![no_std]

use soroban_sdk::{Address, BytesN, Env, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Pocket smart account");

mod auth;
mod contract;
mod errors;
mod events;
#[cfg(test)]
mod test;
pub mod types;

#[contract]
pub struct Pocket;

pub trait PocketTrait {
    /// * `chip` - Bound SEC1 pubkey — the sole authority over this purse.
    /// * `curve` - Which algorithm that key signs with; verification is linked, so no
    ///   external verifier address is stored and none can be re-pointed.
    /// * `owner` - Durable Chimp account that can recover / receive this purse.
    /// * `upgrade_policy` - What the holder chose at onboarding.
    fn __constructor(
        e: &Env,
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

    /// Durable Chimp account behind this purse.
    fn owner(e: &Env) -> Address;

    /// Hand the purse to a new account — the card-transfer path. Authorized by the
    /// current owner (nfc-nft calls this inside its atomic `transfer`).
    fn set_owner(e: &Env, new_owner: Address);

    /// Recover the purse float to `to`. Authorized by `owner`, not the chip — this is
    /// the lost-card path, so it must work when the chip is gone.
    fn sweep(e: &Env, token: Address, to: Address);
}
