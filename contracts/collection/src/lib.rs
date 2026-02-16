#![no_std]
#![allow(dead_code)]

use soroban_sdk::{Address, BytesN, Env, String, Vec, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO Collection");

mod contract;

mod errors;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct Collection;

pub trait CollectionTrait {
    fn __constructor(e: &Env, admin: Address);

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    fn create_collection(
        e: &Env,
        wasm_hash: BytesN<32>,
        name: String,
        symbol: String,
        uri: String,
        max_tokens: u32,
    ) -> Address;

    fn assign_collectible(e: &Env, collection: Address, to: Address, token_id: u32);

    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)>;
}
