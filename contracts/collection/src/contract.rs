//! NFC Collection

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String, Vec};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, Collection, CollectionArgs, CollectionClient, CollectionTrait};

#[contracttype]
pub enum DataKey {
    Admin,
}

#[contracttype]
pub enum CollectionKey {
    NFTContract,
    Collections,
    Collectibles(Address),
}


#[contractimpl]
impl CollectionTrait for Collection {

    fn __constructor(e: &Env, admin: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        e.deployer().update_current_contract_wasm(wasm_hash.clone());
    }

    fn create_collection(e: &Env, wasm_hash: BytesN<32>, name: String, symbol: String, uri: String, max_tokens: u32) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        let salt: BytesN<32> = e.crypto().sha256(&symbol.to_bytes()).into();
        let deployer = e.deployer().with_current_contract(salt);
        let contract_address = deployer.deploy_v2(wasm_hash, (name, symbol, uri, max_tokens));

        let mut collections: Vec<Address> = e.storage().instance().get(&CollectionKey::Collections).unwrap_or(Vec::new(&e));
        collections.push_back(contract_address.clone());
        e.storage().instance().set(&CollectionKey::Collections, &contract_address);
    }

    fn assign_collectible(e: &Env, collection: Address, to: Address, token_id: u32) {
        collection.require_auth();

        let mut collectibles: Vec<(Address, u32)> = e.storage().instance().get(&CollectionKey::Collectibles(to.clone())).unwrap_or(Vec::new(&e));
        collectibles.push_back((collection, token_id));
        e.storage().instance().set(&CollectionKey::Collectibles(to), &collectibles);
    }

    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)> {
        e.storage().instance().get(&CollectionKey::Collectibles(from.clone())).unwrap_or(Vec::new(&e))
    }

}
