//! NFC Collection

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, Collection, CollectionArgs, CollectionClient, CollectionTrait};

#[contracttype]
pub enum DataKey {
    Admin,
}

#[contracttype]
pub enum CollectionKey {
    NFTContract,
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

        events::Upgrade { admin, wasm_hash: wasm_hash.into() }.publish(e);
    }


}
