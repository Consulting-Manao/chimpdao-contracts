#![cfg(test)]

extern crate std;

use soroban_sdk::{Address, BytesN, Env, testutils::Address as _};

use chimpdao_chip_auth::Curve;

use crate::{PocketFactory, PocketFactoryClient, UpgradePolicy};

mod pocket_contract {
    // The generated client covers `__check_auth`, whose spec names `Context`.
    #[allow(unused_imports)]
    use soroban_sdk::auth::Context;

    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/chimpdao_pocket.wasm");
}

/// A factory in the state it needs before it can deploy: NFT registry + pinned wasm.
fn setup(e: &Env) -> PocketFactoryClient<'_> {
    e.mock_all_auths();
    let admin = Address::generate(e);
    let id = e.register(PocketFactory, (&admin,));
    let client = PocketFactoryClient::new(e, &id);
    let wasm = e.deployer().upload_contract_wasm(pocket_contract::WASM);
    client.set_pocket_wasm_hash(&wasm);
    client
}

fn pk(e: &Env, fill: u8) -> BytesN<65> {
    BytesN::from_array(e, &[fill; 65])
}

#[test]
fn get_account_empty() {
    let e = Env::default();
    let client = setup(&e);
    assert_eq!(client.get_account(&pk(&e, 4)), None);
}

#[test]
fn create_account_idempotent() {
    let e = Env::default();
    let client = setup(&e);
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
    let client = setup(&e);
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
    let id = e.register(PocketFactory, (&admin,));
    let client = PocketFactoryClient::new(&e, &id);
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
    let client = setup(&e);
    assert!(client.pocket_wasm_hash().is_some());
}
