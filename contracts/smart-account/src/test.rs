#![cfg(test)]

extern crate std;

use soroban_sdk::{
    Address, BytesN, Env, IntoVal, Symbol,
    auth::Context,
    testutils::Address as _,
    token::{StellarAssetClient, TokenClient},
};

use crate::errors::SmartAccountError;
use crate::{SmartAccount, SmartAccountClient, types};

/// Not a real point — these tests never verify a signature. Live Infineon/DUOX is the
/// real proof; see chimpdao-terminal hardware runs.
fn chip_pk(e: &Env) -> BytesN<65> {
    BytesN::from_array(e, &[4u8; 65])
}

fn setup<'a>(e: &'a Env) -> (SmartAccountClient<'a>, Address, Address) {
    let collection = Address::generate(e);
    let owner = Address::generate(e);
    let id = e.register(
        SmartAccount,
        (
            collection,
            chip_pk(e),
            types::Curve::Secp256k1,
            owner.clone(),
            types::UpgradePolicy::Manual,
        ),
    );
    (SmartAccountClient::new(e, &id), id, owner)
}

#[test]
fn constructor_stores_owner_and_policy() {
    let e = Env::default();
    let (client, _, owner) = setup(&e);
    assert_eq!(client.owner(), owner);
    assert_eq!(client.upgrade_policy(), types::UpgradePolicy::Manual);
}

/// `__check_auth` is the only authorization path; a signature that does not verify
/// against the Instance chip must be rejected.
#[test]
fn check_auth_rejects_a_bad_signature() {
    let e = Env::default();
    let (_, id, _) = setup(&e);
    let bad = types::ChipAuth::Secp256k1(types::Secp256k1Auth {
        signature: BytesN::from_array(&e, &[1u8; 64]),
        recovery_id: 0,
    });
    let ctx: soroban_sdk::Vec<Context> = soroban_sdk::Vec::new(&e);

    let res: Result<(), Result<SmartAccountError, _>> = e.try_invoke_contract_check_auth(
        &id,
        &BytesN::from_array(&e, &[0xA1; 32]),
        bad.into_val(&e),
        &ctx,
    );
    assert_eq!(res, Err(Ok(SmartAccountError::InvalidSignature)));
}

/// Lost-card recovery: `sweep` answers to the owner, not the chip.
#[test]
fn sweep_moves_the_float_to_the_owner() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, id, owner) = setup(&e);

    let sac = e.register_stellar_asset_contract_v2(Address::generate(&e));
    let token = sac.address();
    StellarAssetClient::new(&e, &token).mint(&id, &500);

    client.sweep(&token, &owner);
    assert_eq!(TokenClient::new(&e, &token).balance(&id), 0);
    assert_eq!(TokenClient::new(&e, &token).balance(&owner), 500);
}

#[test]
#[should_panic(expected = "Error(Auth, InvalidAction)")]
fn sweep_requires_owner_auth() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, id, owner) = setup(&e);
    let sac = e.register_stellar_asset_contract_v2(Address::generate(&e));
    StellarAssetClient::new(&e, &sac.address()).mint(&id, &10);

    e.set_auths(&[]);
    client.sweep(&sac.address(), &owner);
}

#[test]
fn earn_link_and_positions_round_trip() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, _, _) = setup(&e);

    assert!(client.get_earn().is_none());
    client.set_earn(&types::EarnLink {
        account: Address::generate(&e),
        context_rule_id: 3,
        verifier: Address::generate(&e),
    });
    assert_eq!(client.get_earn().unwrap().context_rule_id, 3);
    client.clear_earn();
    assert!(client.get_earn().is_none());

    let strategy = Symbol::new(&e, "blend");
    let position = types::Position {
        strategy_id: strategy.clone(),
        underlying: Address::generate(&e),
        meta: soroban_sdk::Map::new(&e),
        amount_hint: Some(42),
    };
    client.upsert_position(&position);
    client.upsert_position(&position); // idempotent — no duplicate id row
    assert_eq!(client.get_positions().len(), 1);
    client.clear_position(&strategy);
    assert_eq!(client.get_positions().len(), 0);
}
