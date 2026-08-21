//! Metadata + rejection paths. Mint/claim/transfer happy paths are proven on live
//! hardware (testnet txs from chimpdao-terminal), not simulated here.
#![cfg(test)]

extern crate std;

use chimpdao_chip_auth::{ChipAuth, Secp256k1Auth};
use soroban_sdk::{Address, Bytes, BytesN, Env, String, testutils::Address as _};

use crate::contract::u32_to_decimal_bytes;
use crate::{NFCtoNFT, NFCtoNFTClient};

mod collection {
    use super::*;
    use soroban_sdk::{contract, contractimpl};

    #[contract]
    pub struct Mock;
    #[contractimpl]
    impl Mock {
        pub fn assign_collectible(_e: &Env, _collection: Address, _to: Address, _token_id: u32) {}
    }
}

/// An account that lists exactly one card — the `has_card` surface nfc-nft checks.
mod account {
    use super::*;
    use soroban_sdk::{contract, contractimpl};

    #[contract]
    pub struct Mock;
    #[contractimpl]
    impl Mock {
        pub fn __constructor(e: &Env, member: BytesN<65>) {
            e.storage().instance().set(&0u32, &member);
        }
        pub fn has_card(e: &Env, key: BytesN<65>) -> bool {
            let member: BytesN<65> = e.storage().instance().get(&0u32).unwrap();
            member == key
        }
    }
}

fn create_client<'a>(e: &Env, admin: &Address) -> NFCtoNFTClient<'a> {
    let collection_id = e.register(collection::Mock, ());
    let address = e.register(
        NFCtoNFT,
        (
            admin,
            collection_id,
            &String::from_str(e, "TestNFT"),
            &String::from_str(e, "TNFT"),
            &String::from_str(e, "ipfs://abcd"),
            &10_000u32,
        ),
    );
    NFCtoNFTClient::new(e, &address)
}

fn bad_auth(e: &Env) -> ChipAuth {
    ChipAuth::Secp256k1(Secp256k1Auth {
        signature: BytesN::from_array(e, &[1u8; 64]),
        recovery_id: 0,
    })
}

fn chip_pk(e: &Env) -> BytesN<65> {
    BytesN::from_array(e, &[4u8; 65])
}

#[test]
fn metadata_is_stored() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    assert_eq!(client.name(), String::from_str(&e, "TestNFT"));
    assert_eq!(client.symbol(), String::from_str(&e, "TNFT"));
}

#[test]
fn u32_to_decimal_bytes_covers_edges() {
    let e = Env::default();
    for (value, want) in [(0u32, "0"), (7, "7"), (10, "10"), (u32::MAX, "4294967295")] {
        assert_eq!(
            u32_to_decimal_bytes(&e, value),
            Bytes::from_slice(&e, want.as_bytes())
        );
    }
}

/// A garbage attestation must not mint, whatever the admin authorizes.
#[test]
#[should_panic(expected = "Error(Contract, #200)")]
fn mint_rejects_a_bad_attestation() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    client.mint(
        &bad_auth(&e),
        &chip_pk(&e),
        &chimpdao_chip_auth::Curve::Secp256k1,
        &1,
    );
}

/// The verify oracle answers false for a card the registry has never minted —
/// callers get a clean rejection, not a trap.
#[test]
fn verify_for_card_rejects_unknown_cards() {
    let e = Env::default();
    let client = create_client(&e, &Address::generate(&e));
    let digest = Bytes::from_slice(&e, &[9u8; 32]);
    assert!(!client.verify_for_card(&chip_pk(&e), &digest, &bad_auth(&e)));
}

/// Soulbound: a destination that does not list the card is rejected before any
/// signature work — here a plain generated address that is no account at all.
#[test]
#[should_panic(expected = "Error(Contract, #214)")]
fn claim_rejects_a_non_member_destination() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    client.claim(&Address::generate(&e), &bad_auth(&e), &chip_pk(&e), &1);
}

/// The counterpart: a destination that lists the card passes the membership gate and
/// fails later at the (unminted) curve lookup instead.
#[test]
#[should_panic(expected = "Error(Contract, #213)")]
fn claim_passes_membership_for_a_holder_account() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));

    let holder = e.register(account::Mock, (chip_pk(&e),));
    client.claim(&holder, &bad_auth(&e), &chip_pk(&e), &1);
}

// --- ERC-7496 traits + the purse pointer ------------------------------------
//
// Minting needs a real chip signature, so these plant a token straight into storage
// rather than going through `mint`. That is the same token state a mint produces —
// `PublicKey(id)` is the only key the trait surface reads — and it keeps the guards
// under test without dragging a signing harness back into the crate.

/// A factory that knows one card's purse, like `pocket-factory::get_account`.
mod factory {
    use super::*;
    use soroban_sdk::{contract, contractimpl};

    #[contract]
    pub struct Mock;
    #[contractimpl]
    impl Mock {
        pub fn __constructor(e: &Env, card: BytesN<65>, pocket: Address) {
            e.storage().instance().set(&0u32, &(card, pocket));
        }
        pub fn get_account(e: &Env, public_key: BytesN<65>) -> Option<Address> {
            let (card, pocket): (BytesN<65>, Address) = e.storage().instance().get(&0u32).unwrap();
            (card == public_key).then_some(pocket)
        }
    }
}

/// A factory whose `get_account` traps — the failure `pocket()` must absorb.
mod broken_factory {
    use super::*;
    use soroban_sdk::{contract, contractimpl};

    #[contract]
    pub struct Mock;
    #[contractimpl]
    impl Mock {
        pub fn get_account(_e: &Env, _public_key: BytesN<65>) -> Option<Address> {
            panic!("factory is down")
        }
    }
}

/// Put token 0 on the card, bypassing the attestation.
fn plant_token(e: &Env, client: &NFCtoNFTClient) {
    use crate::contract::NFTStorageKey;
    let address = client.address.clone();
    e.as_contract(&address, || {
        e.storage()
            .persistent()
            .set(&NFTStorageKey::PublicKey(0u32), &chip_pk(e));
    });
}

#[test]
fn tier_defaults_to_zero_and_round_trips() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    plant_token(&e, &client);

    let tier = String::from_str(&e, "tier");
    assert_eq!(client.trait_value(&0, &tier), 0);

    client.set_trait(&0, &tier, &2);
    assert_eq!(client.trait_value(&0, &tier), 2);
    assert_eq!(
        client.trait_values(&0, &soroban_sdk::vec![&e, tier]),
        soroban_sdk::vec![&e, 2i128]
    );
}

/// `balance` used to be a trait and is not one any more: a card's money lives on the
/// purse, which answers for itself. Asking for it is an unknown key, not a zero.
#[test]
#[should_panic(expected = "Error(Contract, #216)")]
fn balance_is_not_a_trait() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    plant_token(&e, &client);

    client.trait_value(&0, &String::from_str(&e, "balance"));
}

#[test]
#[should_panic(expected = "Error(Contract, #216)")]
fn only_declared_traits_can_be_set() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    plant_token(&e, &client);

    client.set_trait(&0, &String::from_str(&e, "balance"), &1);
}

/// Reads are free to whoever simulates them, so the batch helper is capped.
#[test]
#[should_panic(expected = "Error(Contract, #218)")]
fn trait_values_is_capped() {
    let e = Env::default();
    let client = create_client(&e, &Address::generate(&e));
    plant_token(&e, &client);

    let mut keys = soroban_sdk::Vec::new(&e);
    for _ in 0..33 {
        keys.push_back(String::from_str(&e, "tier"));
    }
    client.trait_values(&0, &keys);
}

#[test]
fn pocket_resolves_the_card_purse_through_the_factory() {
    let e = Env::default();
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);
    plant_token(&e, &client);

    // No factory configured yet: a pointer nobody set is None, not a trap.
    assert_eq!(client.pocket(&0), None);

    let purse = Address::generate(&e);
    let factory_id = e.register(factory::Mock, (chip_pk(&e), purse.clone()));
    client.set_factory(&factory_id);

    assert_eq!(client.pocket(&0), Some(purse));
}

/// A factory that traps must read as "no purse", never fail the call: this is the
/// pointer every outside reader follows, and it points at a contract we do not own.
#[test]
fn pocket_absorbs_a_broken_factory() {
    let e = Env::default();
    e.mock_all_auths();
    let client = create_client(&e, &Address::generate(&e));
    plant_token(&e, &client);

    client.set_factory(&e.register(broken_factory::Mock, ()));
    assert_eq!(client.pocket(&0), None);
}

/// Unknown token fails as a missing token everywhere, before any trait lookup.
#[test]
#[should_panic(expected = "Error(Contract, #201)")]
fn traits_reject_an_unknown_token() {
    let e = Env::default();
    let client = create_client(&e, &Address::generate(&e));
    client.trait_value(&7, &String::from_str(&e, "tier"));
}
