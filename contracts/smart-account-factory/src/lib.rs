#![no_std]

use soroban_sdk::{contract, contractmeta, Address, BytesN, Env};

contractmeta!(key = "Description", val = "ChimpDAO per-chip Pocket account factory");

mod contract;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct SmartAccountFactory;

pub use chimpdao_chip_auth::Curve;

pub trait SmartAccountFactoryTrait {
    fn __constructor(e: &Env, admin: Address);

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// Admin sets NFT collection passed into every new Pocket deploy.
    fn set_collection(e: &Env, collection_contract: Address);

    fn collection(e: &Env) -> Option<Address>;

    /// Deploy a Pocket account for `public_key` (salt = sha256(pubkey)), or return existing.
    fn create_account(
        e: &Env,
        wasm_hash: BytesN<32>,
        public_key: BytesN<65>,
        curve: Curve,
    ) -> Address;

    fn get_account(e: &Env, public_key: BytesN<65>) -> Option<Address>;
}
