#![cfg(test)]

extern crate std;

use soroban_sdk::{
    testutils::Address as _,
    token::{StellarAssetClient, TokenClient},
    Address, Bytes, BytesN, Env,
};

use crate::{types, SmartAccount, SmartAccountClient};

fn chip_pk(e: &Env) -> BytesN<65> {
    BytesN::from_array(e, &[4u8; 65])
}

fn k1_auth(e: &Env) -> types::ChipAuth {
    types::ChipAuth::Secp256k1(types::Secp256k1Auth {
        signature: BytesN::from_array(e, &[1u8; 64]),
        recovery_id: 0,
    })
}

fn setup(e: &Env) -> (SmartAccountClient<'_>, Address) {
    e.mock_all_auths();
    let collection = Address::generate(e);
    let id = e.register(
        SmartAccount,
        (collection, chip_pk(e), types::Curve::Secp256k1),
    );
    let client = SmartAccountClient::new(e, &id);
    (client, id)
}

#[test]
fn get_nonce_defaults_to_zero() {
    let e = Env::default();
    let (client, _) = setup(&e);
    assert_eq!(client.get_nonce(), 0);
}

#[test]
fn get_earn_defaults_to_none() {
    let e = Env::default();
    let (client, _) = setup(&e);
    assert!(client.get_earn().is_none());
}

#[test]
fn collection_is_stored() {
    let e = Env::default();
    e.mock_all_auths();
    let collection = Address::generate(&e);
    let id = e.register(
        SmartAccount,
        (collection.clone(), chip_pk(&e), types::Curve::Secp256k1),
    );
    let client = SmartAccountClient::new(&e, &id);
    assert_eq!(client.collection(), collection);
}

#[test]
#[should_panic(expected = "Error(Contract, #202)")]
fn transfer_rejects_non_positive_amount() {
    let e = Env::default();
    let (client, contract) = setup(&e);
    let issuer = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(issuer);
    let token = sac.address();
    let to = Address::generate(&e);
    let msg = Bytes::from_slice(&e, b"pay");
    client.transfer(&token, &contract, &to, &0, &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #200)")]
fn transfer_rejects_wrong_from() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let issuer = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(issuer);
    let token = sac.address();
    let other = Address::generate(&e);
    let to = Address::generate(&e);
    let msg = Bytes::from_slice(&e, b"pay");
    client.transfer(&token, &other, &to, &1, &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn transfer_rejects_bad_signature() {
    let e = Env::default();
    let (client, contract) = setup(&e);
    let issuer = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(issuer);
    let token = sac.address();
    let to = Address::generate(&e);
    let msg = Bytes::from_slice(&e, b"pay");
    // Junk k1 auth → recover ≠ Instance Chip.
    client.transfer(&token, &contract, &to, &1, &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn transfer_rejects_auth_curve_mismatch() {
    let e = Env::default();
    e.mock_all_auths();
    let collection = Address::generate(&e);
    let pk = chip_pk(&e);
    let contract = e.register(
        SmartAccount,
        (collection, pk, types::Curve::Secp256k1),
    );
    let client = SmartAccountClient::new(&e, &contract);
    let issuer = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(issuer);
    let token = sac.address();
    let to = Address::generate(&e);
    let msg = Bytes::from_slice(&e, b"pay");
    let auth = types::ChipAuth::Secp256r1(types::Secp256r1Auth {
        signature: BytesN::from_array(&e, &[1u8; 64]),
        rnd_b: BytesN::from_array(&e, &[2u8; 16]),
    });
    client.transfer(&token, &contract, &to, &1, &msg, &auth, &1);
}

#[test]
fn get_positions_defaults_empty() {
    let e = Env::default();
    let (client, _) = setup(&e);
    assert_eq!(client.get_positions().len(), 0);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn upsert_position_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let mut meta = soroban_sdk::Map::new(&e);
    meta.set(
        soroban_sdk::Symbol::new(&e, "pool"),
        Bytes::from_slice(&e, b"CPOOL"),
    );
    let position = types::Position {
        strategy_id: soroban_sdk::Symbol::new(&e, "blend"),
        underlying: Address::generate(&e),
        meta,
        amount_hint: Some(1),
    };
    let msg = Bytes::from_slice(&e, b"upsert_position");
    client.upsert_position(&position, &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn clear_position_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let msg = Bytes::from_slice(&e, b"clear_position");
    client.clear_position(
        &soroban_sdk::Symbol::new(&e, "blend"),
        &msg,
        &k1_auth(&e),
        &1,
    );
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn set_earn_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let link = types::EarnLink {
        account: Address::generate(&e),
        context_rule_id: 1,
        verifier: Address::generate(&e),
    };
    let msg = Bytes::from_slice(&e, b"set_earn");
    client.set_earn(&link, &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn clear_earn_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let msg = Bytes::from_slice(&e, b"clear_earn");
    client.clear_earn(&msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn upgrade_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let msg = Bytes::from_slice(&e, b"upgrade");
    client.upgrade(&BytesN::from_array(&e, &[9u8; 32]), &msg, &k1_auth(&e), &1);
}

#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn set_collection_rejects_bad_signature() {
    let e = Env::default();
    let (client, _) = setup(&e);
    let msg = Bytes::from_slice(&e, b"set_collection");
    client.set_collection(&Address::generate(&e), &msg, &k1_auth(&e), &1);
}

#[test]
fn balance_reads_sac_holdings() {
    let e = Env::default();
    e.mock_all_auths();
    let collection = Address::generate(&e);
    let contract_id = e.register(
        SmartAccount,
        (collection, chip_pk(&e), types::Curve::Secp256k1),
    );
    let client = SmartAccountClient::new(&e, &contract_id);
    let issuer = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(issuer);
    let token = sac.address();
    StellarAssetClient::new(&e, &token).mint(&contract_id, &1_000_000);
    assert_eq!(TokenClient::new(&e, &token).balance(&contract_id), 1_000_000);
    assert_eq!(client.balance(&token), 1_000_000);
}
