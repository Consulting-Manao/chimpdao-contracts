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

    /// Create a collection.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `wasm_hash` - Contract to use to bootstrap a new collection.
    /// * `name` - Name of the collection.
    /// * `symbol` - Symbol of the collection (4 chars).
    /// * `uri` - Uniform Resource Identifier of the collection.
    /// * `max_tokens` - Max number of tokens.
    ///
    /// # Returns
    ///
    /// The address of the newly created collection.
    ///
    /// # Panics
    ///
    /// * If the caller is not the admin of the collection contract.
    ///
    /// # Events
    ///
    /// * topics - `["create_collection"]`
    /// * data - `[symbol: String, contract_address: Address]`
    fn create_collection(
        e: &Env,
        wasm_hash: BytesN<32>,
        name: String,
        symbol: String,
        uri: String,
        max_tokens: u32,
    ) -> Address;

    /// Assign a collectible of a collection to someone.
    ///
    /// On-chain indexing of items. Used for instance when claiming/transfer.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `collection` - Contract to use to bootstrap a new collection.
    /// * `to` - Account of the claimant/recipient.
    /// * `token_id` - Token id as a number.
    ///
    /// # Panics
    ///
    /// * If the caller is not the collection contract itself.
    /// * If the collection does not exist.
    fn assign_collectible(e: &Env, collection: Address, to: Address, token_id: u32);

    /// Get all collectibles of an address.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `from` - Address owning the collectibles.
    ///
    /// # Returns
    ///
    /// A vector of collectibles as tuples (addresses of the collection, token ID).
    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)>;

    /// Get all collection addresses.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    ///
    /// # Returns
    ///
    /// A vector of collection addresses.
    fn collections(e: &Env) -> Vec<Address>;
}
