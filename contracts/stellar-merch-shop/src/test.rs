extern crate std;

use soroban_sdk::{testutils::Address as _, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;

// Test constants for valid signature and public key
const TEST_PUBLIC_KEY: [u8; 65] = [
    0x04, 0x34, 0x32, 0x6c, 0x74, 0x99, 0x7e, 0xbb, 0x86, 0xdd, 0xa9, 0x9c, 0x8e, 0x76, 0x3b, 0xa8,
    0xc8, 0x08, 0xc0, 0xbd, 0x60, 0x8c, 0x95, 0xca, 0xc0, 0x62, 0xc8, 0x9c, 0x3a, 0x9b, 0x6f, 0xa3,
    0xb8, 0x26, 0x73, 0xc9, 0x5e, 0xca, 0xe1, 0xb0, 0xfb, 0x77, 0x06, 0x00, 0x02, 0x58, 0x0a, 0xa5,
    0x4c, 0x7b, 0x0f, 0xe5, 0x54, 0x59, 0x6f, 0x93, 0x22, 0x42, 0x73, 0x90, 0xa4, 0x90, 0x37, 0x8c,
    0x9d,
];

const TEST_SIGNATURE_R: [u8; 32] = [
    0x8d, 0x94, 0xa7, 0x75, 0xe5, 0xc0, 0xd2, 0x0f, 0x78, 0x34, 0x5f, 0xe3, 0x77, 0xe8, 0xa3, 0x01,
    0x1f, 0x7a, 0xb9, 0xc0, 0x37, 0x9b, 0xea, 0x66, 0xc9, 0x37, 0x2b, 0x11, 0x94, 0x65, 0x4d, 0xb8,
];

const TEST_SIGNATURE_S: [u8; 32] = [
    0x97, 0x72, 0xc5, 0x2b, 0x63, 0xca, 0xdb, 0x30, 0x6a, 0xd4, 0xe2, 0x61, 0xd2, 0x50, 0xaa, 0x01,
    0xc2, 0x39, 0x05, 0x06, 0xb2, 0x8f, 0x25, 0x5b, 0xae, 0xca, 0xbc, 0xe4, 0x45, 0x10, 0x69, 0x70,
];

const TEST_SIGNATURE_R_NONCE_2: [u8; 32] = [
    0xe8, 0x2a, 0xb8, 0x63, 0xc1, 0xe3, 0x68, 0x45, 0x32, 0xc6, 0xb7, 0xa7, 0xfc, 0x68, 0x07, 0x13,
    0x56, 0xf9, 0x07, 0x35, 0xec, 0xe5, 0xad, 0x6a, 0x05, 0xaf, 0xf0, 0x87, 0xb0, 0xb8, 0x59, 0xf8,
];

const TEST_SIGNATURE_S_NONCE_2: [u8; 32] = [
    0xe4, 0xd6, 0xf6, 0x9d, 0xce, 0x3e, 0x06, 0xa9, 0x11, 0xe4, 0x01, 0xde, 0x7a, 0x75, 0x50, 0x5c,
    0xed, 0x6f, 0x17, 0x35, 0x4a, 0x19, 0xd7, 0x53, 0x07, 0xa1, 0xe8, 0xe7, 0x3c, 0x20, 0xd8, 0xa5,
];

// Normalize s value for ECDSA signatures (required by Soroban, same as webapp)
fn normalize_s(s: &[u8; 32]) -> [u8; 32] {
    const HALF_ORDER: [u8; 32] = [
        0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x5D, 0x57, 0x6E, 0x73, 0x57, 0xA4, 0x50, 0x1D,
    ];
    const CURVE_ORDER: [u8; 32] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
        0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B, 0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41,
    ];

    // Check if s > half_order
    let mut s_greater_than_half = false;
    for i in 0..32 {
        if s[i] > HALF_ORDER[i] {
            s_greater_than_half = true;
            break;
        } else if s[i] < HALF_ORDER[i] {
            break;
        }
    }

    if s_greater_than_half {
        // s = n - s
        let mut result = [0u8; 32];
        let mut borrow = 0u16;
        for i in (0..32).rev() {
            let curve_byte = CURVE_ORDER[i] as u16;
            let s_byte = s[i] as u16;
            let total_to_subtract = s_byte + borrow;

            if curve_byte >= total_to_subtract {
                result[i] = (curve_byte - total_to_subtract) as u8;
                borrow = 0;
            } else {
                result[i] = ((256u16 + curve_byte) - total_to_subtract) as u8;
                borrow = 1;
            }
        }
        result
    } else {
        *s
    }
}

// Helper to create test signature with proper normalization and find recovery ID
fn create_test_signature_and_recovery_id(
    e: &Env,
    message: &Bytes,
    nonce: u32,
    sig_r: &[u8; 32],
    sig_s: &[u8; 32],
) -> (BytesN<64>, u32) {
    let public_key = BytesN::from_array(e, &TEST_PUBLIC_KEY);

    let mut builder = Bytes::new(e);
    builder.append(message);
    builder.append(&nonce.to_xdr(e));
    let message_hash = e.crypto().sha256(&builder);

    let s_normalized = normalize_s(sig_s);
    let mut sig_bytes = [0u8; 64];
    sig_bytes[..32].copy_from_slice(sig_r);
    sig_bytes[32..].copy_from_slice(&s_normalized);
    let signature = BytesN::from_array(e, &sig_bytes);

    // Find correct recovery ID
    for rid in 0u32..=3u32 {
        let recovered = e.crypto().secp256k1_recover(&message_hash, &signature, rid);
        if recovered == public_key {
            return (signature, rid);
        }
    }

    panic!("No valid recovery ID found for test signature");
}

use crate::{StellarMerchShop, StellarMerchShopClient};

fn create_client<'a>(e: &Env, admin: &Address) -> StellarMerchShopClient<'a> {
    let address = e.register(
        StellarMerchShop,
        (
            admin,
            &String::from_str(e, "TestNFT"),
            &String::from_str(e, "TNFT"),
            &String::from_str(e, "ipfs://abcd"),
            &10_000u64, // max_tokens
        ),
    );
    StellarMerchShopClient::new(e, &address)
}

#[test]
fn test_metadata() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

    let name = client.name();
    assert_eq!(name, String::from_str(&e, "TestNFT"));
    
    let symbol = client.symbol();
    assert_eq!(symbol, String::from_str(&e, "TNFT"));
}


#[test]
fn test_claim() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let claimant = Address::generate(&e);
    let client = create_client(&e, &admin);

    let message = Bytes::from_slice(&e, b"test message for minting");
    let mint_nonce: u32 = 1;
    let claim_nonce: u32 = 2;

    let public_key = BytesN::from_array(&e, &TEST_PUBLIC_KEY);

    // First mint with valid signature (nonce 1)
    let (mint_signature, mint_recovery_id) = create_test_signature_and_recovery_id(
        &e,
        &message,
        mint_nonce,
        &TEST_SIGNATURE_R,
        &TEST_SIGNATURE_S,
    );

    let token_id = client.mint(&message, &mint_signature, &mint_recovery_id, &public_key, &mint_nonce);
    assert_eq!(token_id, 0u64);

    // Verify token is unclaimed after mint
    let owner_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        client.owner_of(&token_id)
    }));
    assert!(owner_result.is_err(), "Token should be unclaimed after mint");

    // Now claim the token with nonce 2
    let (claim_signature, claim_recovery_id) = create_test_signature_and_recovery_id(
        &e,
        &message,
        claim_nonce,
        &TEST_SIGNATURE_R_NONCE_2,
        &TEST_SIGNATURE_S_NONCE_2,
    );

    // Claim the token
    let claimed_token_id = client.claim(&claimant, &message, &claim_signature, &claim_recovery_id, &public_key, &claim_nonce);
    assert_eq!(claimed_token_id, token_id, "Claim should return the same token ID");

    // Verify ownership was transferred
    let owner = client.owner_of(&token_id);
    assert_eq!(owner, claimant, "Token should be owned by claimant after claim");

    // Verify claimant's balance was updated
    let claimant_balance = client.balance(&claimant);
    assert_eq!(claimant_balance, 1u32, "Claimant should have balance of 1 after claiming");

    let token_uri = client.token_uri(&0);
    assert_eq!(token_uri, String::from_str(&e, "ipfs://abcd/0"));
}

#[test]
#[should_panic]
fn test_nonce_reuse_prevention() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

    let message = Bytes::from_slice(&e, b"test message for minting");
    let nonce: u32 = 1;

    let public_key = BytesN::from_array(&e, &TEST_PUBLIC_KEY);

    let (signature, recovery_id) = create_test_signature_and_recovery_id(
        &e,
        &message,
        nonce,
        &TEST_SIGNATURE_R,
        &TEST_SIGNATURE_S,
    );

    // First mint should succeed
    let _token_id = client.mint(&message, &signature, &recovery_id, &public_key, &nonce);

    // Second mint with same nonce should panic (nonce reuse prevention)
    client.mint(&message, &signature, &recovery_id, &public_key, &nonce);
}

#[test]
fn test_u64_to_decimal_bytes() {
    let e = Env::default();

    let test_cases: &[(u64, &str)] = &[
        (0, "0"),
        (1, "1"),
        (9, "9"),
        (10, "10"),
        (99, "99"),
        (100, "100"),
        (999, "999"),
        (1000, "1000"),
        (9999, "9999"),
        (10000, "10000"),
        (12345, "12345"),
        (99999, "99999"),
        (100000, "100000"),
        (999999, "999999"),
    ];

    for (value, expected_str) in test_cases.iter() {
        let result = crate::contract::u64_to_decimal_bytes(&e, *value);
        assert_eq!(result, Bytes::from_slice(&e, expected_str.as_bytes()));
    }
}

