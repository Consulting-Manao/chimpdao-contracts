#![cfg(test)]

extern crate std;

use soroban_sdk::{
    Address, BytesN, Env, IntoVal,
    auth::Context,
    testutils::Address as _,
    token::{StellarAssetClient, TokenClient},
};

use crate::errors::PocketError;
use crate::{Pocket, PocketClient, types};

/// Not a real point — these tests never verify a signature. Live Infineon/DUOX is the
/// real proof; see chimpdao-terminal hardware runs.
fn chip_pk(e: &Env) -> BytesN<65> {
    BytesN::from_array(e, &[4u8; 65])
}

fn setup<'a>(e: &'a Env) -> (PocketClient<'a>, Address, Address) {
    let owner = Address::generate(e);
    let id = e.register(
        Pocket,
        (
            chip_pk(e),
            types::Curve::Secp256k1,
            owner.clone(),
            types::UpgradePolicy::Manual,
        ),
    );
    (PocketClient::new(e, &id), id, owner)
}

#[test]
fn constructor_stores_owner_and_policy() {
    let e = Env::default();
    let (client, _, owner) = setup(&e);
    assert_eq!(client.owner(), owner);
    assert_eq!(client.upgrade_policy(), types::UpgradePolicy::Manual);
}

/// Verification is linked now, so a junk signature is rejected by the crypto itself —
/// there is no verifier address whose verdict could be substituted.
#[test]
fn check_auth_rejects_a_bad_signature() {
    let e = Env::default();
    let bad = types::ChipAuth::Secp256k1(types::Secp256k1Auth {
        signature: BytesN::from_array(&e, &[1u8; 64]),
        recovery_id: 0,
    });
    let ctx: soroban_sdk::Vec<Context> = soroban_sdk::Vec::new(&e);
    let payload: BytesN<32> = BytesN::from_array(&e, &[7u8; 32]);

    let (_, id, _) = setup(&e);
    let got =
        e.try_invoke_contract_check_auth::<PocketError>(&id, &payload, bad.into_val(&e), &ctx);
    assert_eq!(got, Err(Ok(PocketError::InvalidSignature)));
}

/// Card handover: the current owner re-points the purse to the recipient's account.
#[test]
fn set_owner_hands_the_purse_over() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, _, _) = setup(&e);

    let next = Address::generate(&e);
    client.set_owner(&next);
    assert_eq!(client.owner(), next);
}

#[test]
#[should_panic(expected = "Error(Auth, InvalidAction)")]
fn set_owner_requires_current_owner_auth() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, _, _) = setup(&e);

    e.set_auths(&[]);
    client.set_owner(&Address::generate(&e));
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
fn upgrade_policy_round_trips() {
    let e = Env::default();
    e.mock_all_auths();
    let (client, _, _) = setup(&e);
    client.set_upgrade_policy(&types::UpgradePolicy::Managed);
    assert_eq!(client.upgrade_policy(), types::UpgradePolicy::Managed);
}
