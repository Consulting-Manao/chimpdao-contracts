#![cfg(test)]

extern crate std;

use soroban_sdk::{testutils::Address as _, Address, BytesN, Env};

use crate::{Curve, SmartAccountFactory, SmartAccountFactoryClient};

mod smart_account_contract {
    soroban_sdk::contractimport!(
        file = "../../target/wasm32v1-none/release/chimpdao_smart_account.wasm"
    );
}

fn setup(e: &Env) -> (SmartAccountFactoryClient<'_>, Address) {
    e.mock_all_auths();
    let admin = Address::generate(e);
    let id = e.register(SmartAccountFactory, (&admin,));
    let client = SmartAccountFactoryClient::new(e, &id);
    let collection = Address::generate(e);
    client.set_collection(&collection);
    (client, collection)
}

fn pk(e: &Env, fill: u8) -> BytesN<65> {
    BytesN::from_array(e, &[fill; 65])
}

#[test]
fn get_account_empty() {
    let e = Env::default();
    let (client, _) = setup(&e);
    assert_eq!(client.get_account(&pk(&e, 4)), None);
}

#[test]
fn collection_stored() {
    let e = Env::default();
    let (client, collection) = setup(&e);
    assert_eq!(client.collection(), Some(collection));
}

#[test]
fn create_account_idempotent() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let wasm = e
        .deployer()
        .upload_contract_wasm(smart_account_contract::WASM);
    let key = pk(&e, 4);

    let a = client.create_account(&wasm, &key, &Curve::Secp256k1);
    let b = client.create_account(&wasm, &key, &Curve::Secp256k1);
    assert_eq!(a, b);
    assert_eq!(client.get_account(&key), Some(a));
}

#[test]
fn create_account_distinct_per_chip() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let wasm = e
        .deployer()
        .upload_contract_wasm(smart_account_contract::WASM);

    let a = client.create_account(&wasm, &pk(&e, 4), &Curve::Secp256k1);
    let b = client.create_account(&wasm, &pk(&e, 5), &Curve::Secp256r1);
    assert_ne!(a, b);
}
