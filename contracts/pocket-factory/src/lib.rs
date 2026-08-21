#![no_std]

use soroban_sdk::{Address, BytesN, Env, contract, contractmeta};

contractmeta!(
    key = "Description",
    val = "ChimpDAO per-chip Pocket account factory"
);

mod contract;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct PocketFactory;

pub use chimpdao_chip_auth::{Curve, UpgradePolicy};

pub trait PocketFactoryTrait {
    fn __constructor(e: &Env, admin: Address);

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// Admin pins the Pocket implementation this factory deploys.
    fn set_pocket_wasm_hash(e: &Env, wasm_hash: BytesN<32>);

    fn pocket_wasm_hash(e: &Env) -> Option<BytesN<32>>;

    /// Deploy a Pocket purse for `public_key` (salt = sha256(pubkey)), or return existing.
    ///
    /// * `owner` - the holder's durable Chimp account, for lost-card recovery.
    /// * `upgrade_policy` - the holder's onboarding consent choice.
    fn create_account(
        e: &Env,
        public_key: BytesN<65>,
        curve: Curve,
        owner: Address,
        upgrade_policy: UpgradePolicy,
    ) -> Address;

    fn get_account(e: &Env, public_key: BytesN<65>) -> Option<Address>;
}
