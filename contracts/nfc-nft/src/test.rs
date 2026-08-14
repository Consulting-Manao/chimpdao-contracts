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
        &BytesN::from_array(&e, &[4u8; 65]),
        &chimpdao_chip_auth::Curve::Secp256k1,
        &1,
    );
}
