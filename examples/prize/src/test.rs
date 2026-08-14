//! The example's own guards. Chip verification is exercised on hardware via nfc-nft.
#![cfg(test)]

extern crate std;

use soroban_sdk::{Address, Env, testutils::Address as _, token};

use crate::{Prize, PrizeClient};

fn setup<'a>(e: &'a Env) -> (PrizeClient<'a>, Address, Address, Address) {
    e.mock_all_auths();
    let admin = Address::generate(e);
    let depositor = Address::generate(e);
    let nfc = Address::generate(e);

    let sac = e.register_stellar_asset_contract_v2(Address::generate(e));
    let token = sac.address();
    token::StellarAssetClient::new(e, &token).mint(&depositor, &1000);

    let id = e.register(Prize, (admin, token.clone(), nfc.clone()));
    (PrizeClient::new(e, &id), token, depositor, nfc)
}

/// The point of the example: the NFC contract is bound at construction, so a caller
/// cannot substitute one that reports them as the owner of any chip.
#[test]
fn nfc_contract_is_bound_at_construction() {
    let e = Env::default();
    let (client, _, _, nfc) = setup(&e);
    assert_eq!(client.nfc_contract(), nfc);
}

#[test]
#[should_panic(expected = "Error(Contract, #403)")]
fn a_non_positive_deposit_is_rejected() {
    let e = Env::default();
    let (client, _, depositor, _) = setup(&e);
    client.deposit(&depositor, &0, &0);
}
