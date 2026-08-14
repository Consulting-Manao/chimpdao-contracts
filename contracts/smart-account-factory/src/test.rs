#![cfg(test)]

extern crate std;

use soroban_sdk::{Address, BytesN, Env, testutils::Address as _};

use crate::{Curve, SmartAccountFactory, SmartAccountFactoryClient, UpgradePolicy};

mod smart_account_contract {
    // The generated client covers `__check_auth`, whose spec names `Context`.
    #[allow(unused_imports)]
    use soroban_sdk::auth::Context;

    soroban_sdk::contractimport!(
        file = "../../target/wasm32v1-none/release/chimpdao_smart_account.wasm"
    );
}

/// A factory in the state it needs before it can deploy: collection + pinned wasm.
fn setup(e: &Env) -> (SmartAccountFactoryClient<'_>, Address) {
    e.mock_all_auths();
    let admin = Address::generate(e);
    let id = e.register(SmartAccountFactory, (&admin,));
    let client = SmartAccountFactoryClient::new(e, &id);
    let collection = Address::generate(e);
    client.set_collection(&collection);
    let wasm = e
        .deployer()
        .upload_contract_wasm(smart_account_contract::WASM);
    client.set_pocket_wasm_hash(&wasm);
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
    let key = pk(&e, 4);
    let owner = Address::generate(&e);

    let a = client.create_account(&key, &Curve::Secp256k1, &owner, &UpgradePolicy::Managed);
    let b = client.create_account(&key, &Curve::Secp256k1, &owner, &UpgradePolicy::Managed);
    assert_eq!(a, b);
    assert_eq!(client.get_account(&key), Some(a));
}

#[test]
fn create_account_distinct_per_chip() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let owner = Address::generate(&e);

    let a = client.create_account(
        &pk(&e, 4),
        &Curve::Secp256k1,
        &owner,
        &UpgradePolicy::Managed,
    );
    let b = client.create_account(
        &pk(&e, 5),
        &Curve::Secp256k1,
        &owner,
        &UpgradePolicy::Manual,
    );
    assert_ne!(a, b);
}

/// The wasm is pinned in state, not chosen per call.
#[test]
#[should_panic(expected = "Error(Contract, #2)")]
fn create_account_requires_a_pinned_wasm() {
    let e = Env::default();
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let id = e.register(SmartAccountFactory, (&admin,));
    let client = SmartAccountFactoryClient::new(&e, &id);
    client.set_collection(&Address::generate(&e));

    client.create_account(
        &pk(&e, 4),
        &Curve::Secp256k1,
        &Address::generate(&e),
        &UpgradePolicy::Managed,
    );
}

#[test]
fn pocket_wasm_hash_round_trips() {
    let e = Env::default();
    let (client, _) = setup(&e);
    assert!(client.pocket_wasm_hash().is_some());
}
