#![allow(dead_code)]

extern crate std;

use soroban_sdk::token;
use soroban_sdk::{
    Address, Bytes, BytesN, Env, contract, contractimpl, contracttype, testutils::Address as _,
};

use crate::{Prize, PrizeClient};

// Fixed chip public key returned by MockNfc for token_id 0 (65 bytes, uncompressed SEC1)
const MOCK_CHIP_PUBLIC_KEY: [u8; 65] = [
    0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00,
];

// ---------- Mock NFC: no-op verify, fixed public_key/token_id/owner ----------

#[contract]
pub struct MockNfc;

#[contracttype]
enum MockNfcDataKey {
    Owner,
}

#[contractimpl]
impl MockNfc {
    pub fn set_owner(e: &Env, owner: Address) {
        e.storage().instance().set(&MockNfcDataKey::Owner, &owner);
    }

    pub fn public_key(_e: &Env, _token_id: u32) -> BytesN<65> {
        BytesN::from_array(_e, &MOCK_CHIP_PUBLIC_KEY)
    }

    pub fn verify_chip_signature(
        _e: &Env,
        _signer: Bytes,
        _message: Bytes,
        _signature: BytesN<64>,
        _recovery_id: u32,
        _public_key: BytesN<65>,
        _nonce: u32,
    ) {
    }

    pub fn token_id(_e: &Env, _public_key: BytesN<65>) -> u32 {
        0u32
    }

    pub fn owner_of(e: &Env, token_id: u32) -> Address {
        if token_id == 0 {
            e.storage().instance().get(&MockNfcDataKey::Owner).unwrap()
        } else {
            panic!("unknown token_id")
        }
    }
}

// ---------- Token setup: Stellar Asset Contract ----------

fn setup_stellar_asset_and_fund(e: &Env, to: &Address, amount: i128) -> Address {
    let issuer = Address::generate(e);
    let sac = e.register_stellar_asset_contract_v2(issuer.clone());
    let token_address = sac.address();
    let token_stellar = token::StellarAssetClient::new(e, &token_address);
    token_stellar.mint(to, &amount);
    token_address
}

// ---------- Tests ----------

#[test]
fn test_deposit_redeem() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let redeemer = Address::generate(&e);
    let depositor = Address::generate(&e);

    let token = setup_stellar_asset_and_fund(&e, &depositor, 1000_i128);
    let mock_nfc = e.register(MockNfc, ());
    let mock_nfc_client = MockNfcClient::new(&e, &mock_nfc);
    mock_nfc_client.set_owner(&redeemer);

    let prize_id = e.register(Prize, (admin.clone(), token.clone()));
    let prize = PrizeClient::new(&e, &prize_id);

    let chip_pk = BytesN::from_array(&e, &MOCK_CHIP_PUBLIC_KEY);
    assert_eq!(prize.get_redeemable(&chip_pk), 0);

    let token_client = token::TokenClient::new(&e, &token);

    assert_eq!(token_client.balance(&depositor), 1000);

    prize.deposit(&depositor, &100_i128, &mock_nfc, &0u32);

    assert_eq!(token_client.balance(&depositor), 900);
    assert_eq!(prize.get_redeemable(&chip_pk), 100);
    assert_eq!(token_client.balance(&prize_id), 100);

    let chip_pk = BytesN::from_array(&e, &MOCK_CHIP_PUBLIC_KEY);
    let dummy_message = Bytes::from_slice(&e, b"dummy");
    let dummy_sig = BytesN::from_array(&e, &[0u8; 64]);

    assert_eq!(token_client.balance(&redeemer), 0);

    prize.redeem(
        &redeemer,
        &mock_nfc,
        &dummy_message,
        &dummy_sig,
        &0u32,
        &chip_pk,
        &1u32,
    );

    assert_eq!(token_client.balance(&redeemer), 100);
}
