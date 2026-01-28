#![no_std]
#![allow(dead_code)]

use soroban_sdk::{contract, contractmeta, Env, Address, String, BytesN, Bytes};

contractmeta!(key = "Description", val = "ChimpDAO Collection");

mod contract;

#[cfg(test)]
mod test;
mod errors;
mod events;

#[contract]
pub struct Collection;

pub trait CollectionTrait {

    fn __constructor(e: &Env, admin: Address);

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

}