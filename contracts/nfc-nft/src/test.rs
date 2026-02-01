//! Test utilities for NFC chip signature handling
//!
//! ## Generating New Test Signatures
//!
//! To generate new test signatures for different nonces or chips:
//!
//! 1. Generate message hash:
//!    cargo test test_print_message_hash_for_signing -- --nocapture
//!    This prints message hashes for all (signer, nonce) pairs used in tests.
//!
//! 2. Get public key from chip:
//!    uv run --with blocksec2go blocksec2go get_key_info <key_id>
//!    Where <key_id> is 1 for Chip 1, 2 for Chip 2, etc.
//!
//! 3. Generate signature:
//!    uv run --with blocksec2go blocksec2go generate_signature <key_id> <message_hash>
//!    Use the message hash from step 1.
//!
//! 4. Parse DER signature:
//!    Use the parse_der_signature() helper function to extract R and S components.
//!
//! 5. Format for Rust:
//!    Use the format_signature_for_rust() helper function to format as Rust constants.
//!
//! ## Important Notes
//!
//! - Message hash = SHA256(message_bytes || signer.to_xdr() || nonce.to_xdr())
//! - Soroban's to_xdr() for u32 uses type tag 0x00000003, NOT 0x00000004
//! - Signatures must have S normalized (low S form) for Soroban's secp256k1_recover
//! - The normalize_s() function handles this automatically
//! - Recovery ID (0-3) is determined automatically by trying all possibilities

extern crate std;
extern crate alloc;

use alloc::format;
use alloc::vec::Vec;

use soroban_sdk::{crypto::Hash, testutils::Address as _, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;

use crate::{NFCtoNFT, NFCtoNFTClient};

struct TestSignature {
    nonce: u32,
    message: &'static [u8],
    sig_r: [u8; 32],
    sig_s: [u8; 32],
    public_key: [u8; 65],
}

const TEST_MESSAGE: &[u8] = b"test message for minting";

// Public keys from get_key_info
const CHIP1_PUBLIC_KEY: [u8; 65] = [
    0x04, 0x24, 0xf8, 0xcd, 0x2c, 0x99, 0xc9, 0x57, 0x91, 0x59, 0xc9, 0x9c, 0x99, 0x1c, 0xa9, 0x36,
    0x3c, 0x5c, 0x89, 0x6a, 0x33, 0x88, 0xc8, 0x78, 0xe8, 0xa2, 0xf5, 0x78, 0xc1, 0xee, 0xd7, 0xfa,
    0x27, 0x19, 0x44, 0x18, 0x50, 0x43, 0x0a, 0xd8, 0x7d, 0xbd, 0x43, 0x72, 0x96, 0x4a, 0xd2, 0x2d,
    0xc0, 0xc9, 0xaa, 0x29, 0xfb, 0x64, 0x78, 0xd5, 0xf9, 0x72, 0x2b, 0x0e, 0x45, 0x36, 0xd0, 0xdc,
    0x2f,
];

const CHIP2_PUBLIC_KEY: [u8; 65] = [
    0x04, 0x1c, 0x49, 0x15, 0x28, 0x99, 0x4c, 0xd0, 0x62, 0x67, 0x7e, 0x8a, 0x7d, 0x54, 0x26, 0x06,
    0x56, 0x9e, 0x7c, 0xe2, 0x4f, 0x98, 0x37, 0x83, 0x41, 0x87, 0xcc, 0x0a, 0xaa, 0xed, 0x11, 0x3d,
    0x5e, 0x67, 0x7b, 0xd4, 0x56, 0x1e, 0x53, 0xee, 0xc2, 0x26, 0xf8, 0x09, 0x38, 0xf3, 0xd9, 0x9f,
    0x11, 0x8f, 0xfd, 0xa4, 0xbe, 0xcb, 0xbd, 0x87, 0x98, 0xd1, 0xc5, 0x93, 0xcb, 0x11, 0x01, 0xa5,
    0x9d,
];

// Test signatures
const TEST_SIGNATURES: &[TestSignature] = &[
    // Chip 1, nonce 1
    TestSignature {
        nonce: 1,
        message: TEST_MESSAGE,
        sig_r: [
            0xf4, 0x09, 0xa1, 0xdf, 0x1a, 0xe1, 0xee, 0x37, 0x20, 0x04, 0x55, 0xf5, 0x42, 0x2f, 0xa4, 0xb3,
            0x63, 0xec, 0xc3, 0x65, 0xe6, 0xd0, 0x52, 0xd0, 0x81, 0x9a, 0xcf, 0x4a, 0x8a, 0x27, 0x75, 0xe1,
        ],
        sig_s: [
            0x12, 0xce, 0x57, 0xeb, 0x17, 0xa2, 0x41, 0x34, 0x9c, 0x75, 0x21, 0xdb, 0x60, 0xc5, 0x1b, 0x81,
            0x2a, 0x3f, 0x0a, 0xe5, 0xc0, 0x07, 0xd5, 0x1f, 0xb5, 0x26, 0x2f, 0xba, 0x0b, 0x15, 0xf3, 0xae,
        ],
        public_key: CHIP1_PUBLIC_KEY,
    },
    // Chip 1, nonce 2
    TestSignature {
        nonce: 2,
        message: TEST_MESSAGE,
        sig_r: [
            0x56, 0x5e, 0xe7, 0x2b, 0xaf, 0xc7, 0x5a, 0x9c, 0x05, 0x97, 0x98, 0x56, 0x65, 0x91, 0x08, 0x04,
            0x82, 0xea, 0x1d, 0xd5, 0x7a, 0xde, 0xf8, 0xdb, 0xdb, 0x7b, 0xeb, 0x8e, 0x33, 0x9d, 0xc4, 0xfd,
        ],
        sig_s: [
            0x07, 0x4e, 0x17, 0xd4, 0x95, 0x18, 0xb2, 0x58, 0xb0, 0x7b, 0x70, 0x12, 0xac, 0x0e, 0xa6, 0xdb,
            0x44, 0x28, 0xa0, 0x34, 0x1c, 0x26, 0xe0, 0x30, 0x82, 0xca, 0x29, 0xd9, 0xa9, 0x67, 0xa7, 0xcc,
        ],
        public_key: CHIP1_PUBLIC_KEY,
    },
    // Chip 1, nonce 3
    TestSignature {
        nonce: 3,
        message: TEST_MESSAGE,
        sig_r: [
            0x23, 0x83, 0xc6, 0x36, 0x14, 0x14, 0x63, 0xbe, 0x89, 0x5b, 0x21, 0x04, 0x10, 0x2c, 0xdf, 0xc1,
            0x31, 0x31, 0xc1, 0xf6, 0x49, 0xb0, 0x42, 0xd8, 0x31, 0xec, 0x85, 0x1c, 0xc0, 0x50, 0x90, 0x91,
        ],
        sig_s: [
            0xbd, 0x86, 0x53, 0x9a, 0xa5, 0x75, 0xd2, 0xcb, 0xad, 0x55, 0x87, 0xa0, 0xfc, 0xdb, 0x25, 0x2d,
            0x1e, 0x9d, 0xc0, 0xff, 0x14, 0x17, 0x4f, 0x08, 0xb4, 0x1a, 0xe3, 0x8e, 0xc6, 0xb2, 0x1b, 0x49,
        ],
        public_key: CHIP1_PUBLIC_KEY,
    },
    // Chip 2, nonce 3
    TestSignature {
        nonce: 3,
        message: TEST_MESSAGE,
        sig_r: [
            0x43, 0xde, 0xcd, 0x39, 0x22, 0xd5, 0x65, 0x6a, 0xa8, 0xef, 0xfa, 0xcc, 0x90, 0xf6, 0xc7, 0x5c,
            0x0a, 0xe7, 0xbf, 0x84, 0xb4, 0xfb, 0xd6, 0x6a, 0x3a, 0xbd, 0xe1, 0x97, 0x7a, 0xa0, 0x36, 0x34,
        ],
        sig_s: [
            0x67, 0x53, 0x32, 0xc9, 0x86, 0xdc, 0x91, 0xa7, 0x9b, 0xc2, 0xf8, 0x0e, 0x13, 0xb7, 0xac, 0x51,
            0xfe, 0x3c, 0x27, 0x93, 0x7e, 0x39, 0x80, 0x83, 0xc5, 0x6c, 0x40, 0x3a, 0xde, 0x47, 0x2e, 0x5f,
        ],
        public_key: CHIP2_PUBLIC_KEY,
    },
    // Chip 2, nonce 4
    TestSignature {
        nonce: 4,
        message: TEST_MESSAGE,
        sig_r: [
            0x9f, 0x4f, 0x91, 0x56, 0x45, 0xaa, 0xc7, 0xe0, 0x5b, 0x5f, 0x8d, 0xe7, 0x7a, 0xdf, 0xa6, 0xf6,
            0xf8, 0xb6, 0xef, 0xb6, 0xf9, 0x05, 0xcf, 0x5f, 0x65, 0xe5, 0xa6, 0xd6, 0x8f, 0x27, 0x51, 0x8f,
        ],
        sig_s: [
            0xab, 0xeb, 0xc1, 0x7e, 0x5a, 0xda, 0x4e, 0x70, 0xe2, 0x50, 0x0d, 0xd5, 0xec, 0x1e, 0x45, 0x3f,
            0xfe, 0x6d, 0xf6, 0xb6, 0x38, 0x22, 0xe4, 0x72, 0x82, 0x4c, 0xeb, 0x82, 0xb0, 0x1e, 0x18, 0x8d,
        ],
        public_key: CHIP2_PUBLIC_KEY,
    },
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
fn create_test_signature_and_recovery_id(e: &Env, message_hash: &Hash<32>, sig: &TestSignature) -> (BytesN<64>, u32) {
    let public_key = BytesN::from_array(e, &sig.public_key);

    let s_normalized = normalize_s(&sig.sig_s);
    let mut sig_bytes = [0u8; 64];
    // Standard secp256k1 format is [R, S] where R and S are 32 bytes each
    sig_bytes[..32].copy_from_slice(&sig.sig_r);
    sig_bytes[32..].copy_from_slice(&s_normalized);
    let signature = BytesN::from_array(e, &sig_bytes);

    // Find correct recovery ID
    // secp256k1_recover panics on invalid input, so we need to catch panics to try all recovery IDs
    for rid in 0u32..=3u32 {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            e.crypto().secp256k1_recover(message_hash, &signature, rid)
        }));
        
        match result {
            Ok(recovered) => {
        if recovered == public_key {
            return (signature, rid);
                }
            }
            Err(_) => {
                // Recovery failed for this recovery ID, try next one
                continue;
            }
        }
    }

    panic!("No valid recovery ID found for test signature");
}

// Helper function to calculate message hash exactly as contract does (message || signer || nonce)
fn calculate_message_hash(e: &Env, message: &[u8], signer: &Address, nonce: u32) -> Hash<32> {
    let message_bytes = Bytes::from_slice(e, message);
    let signer_xdr = signer.to_xdr(e);
    let nonce_xdr = nonce.to_xdr(e);
    let mut builder = Bytes::new(e);
    builder.append(&message_bytes);
    builder.append(&signer_xdr);
    builder.append(&nonce_xdr);
    e.crypto().sha256(&builder)
}

// Helper function to print message hash for manual signing (new formula: message || signer || nonce)
fn print_message_hash_for_signing_with_signer(e: &Env, message: &[u8], signer: &Address, nonce: u32, label: &str) {
    let message_bytes = Bytes::from_slice(e, message);
    let signer_xdr = signer.to_xdr(e);
    let nonce_xdr = nonce.to_xdr(e);

    let mut builder = Bytes::new(e);
    builder.append(&message_bytes);
    builder.append(&signer_xdr);
    builder.append(&nonce_xdr);
    let message_hash = e.crypto().sha256(&builder);

    let hash_bytes: BytesN<32> = message_hash.clone().into();
    let hash_array = hash_bytes.to_array();

    let mut hash_hex = std::string::String::new();
    for byte in hash_array {
        hash_hex.push_str(&format!("{:02x}", byte));
    }

    std::println!("{}", label);
    std::println!("  Nonce: {}", nonce);
    std::println!("  Message hash (hex): {}", hash_hex);
    std::println!();
}

// Helper function to parse DER signature and extract R and S
// DER format: 0x30 [length] 0x02 [R length] [R bytes] 0x02 [S length] [S bytes]
fn parse_der_signature(der_hex: &str) -> ([u8; 32], [u8; 32]) {
    // Parse hex string to bytes
    let clean_hex = der_hex.strip_prefix("0x").unwrap_or(der_hex);
    let mut der_bytes = Vec::new();
    for i in 0..(clean_hex.len() / 2) {
        let byte_str = &clean_hex[i * 2..i * 2 + 2];
        let byte = u8::from_str_radix(byte_str, 16).expect("Invalid hex string");
        der_bytes.push(byte);
    }
    
    let mut pos = 1; // Skip 0x30 sequence tag
    
    if der_bytes[0] != 0x30 {
        panic!("Invalid DER: expected sequence tag 0x30");
    }
    
    let _seq_len = der_bytes[pos];
    pos += 1;
    
    // Parse R component
    if der_bytes[pos] != 0x02 {
        panic!("Invalid DER: expected integer tag 0x02 for R");
    }
    pos += 1;
    
    let r_len = der_bytes[pos] as usize;
    pos += 1;
    
    let mut r_bytes = der_bytes[pos..pos + r_len].to_vec();
    pos += r_len;
    
    // Remove leading zero if present (for positive numbers)
    if r_bytes.len() > 32 && r_bytes[0] == 0x00 {
        r_bytes = r_bytes[1..].to_vec();
    }
    
    // Pad to 32 bytes if needed
    let mut sig_r = [0u8; 32];
    if r_bytes.len() < 32 {
        sig_r[32 - r_bytes.len()..].copy_from_slice(&r_bytes);
    } else {
        sig_r.copy_from_slice(&r_bytes[r_bytes.len() - 32..]);
    }
    
    // Parse S component
    if der_bytes[pos] != 0x02 {
        panic!("Invalid DER: expected integer tag 0x02 for S");
    }
    pos += 1;
    
    let s_len = der_bytes[pos] as usize;
    pos += 1;
    
    let mut s_bytes = der_bytes[pos..pos + s_len].to_vec();
    
    // Remove leading zero if present (for positive numbers)
    if s_bytes.len() > 32 && s_bytes[0] == 0x00 {
        s_bytes = s_bytes[1..].to_vec();
    }
    
    // Pad to 32 bytes if needed
    let mut sig_s = [0u8; 32];
    if s_bytes.len() < 32 {
        sig_s[32 - s_bytes.len()..].copy_from_slice(&s_bytes);
    } else {
        sig_s.copy_from_slice(&s_bytes[s_bytes.len() - 32..]);
    }
    
    (sig_r, sig_s)
}

// Helper function to format signature arrays as Rust constants
fn format_signature_for_rust(sig_r: [u8; 32], sig_s: [u8; 32]) -> std::string::String {
    let mut result = std::string::String::new();
    
    result.push_str("        sig_r: [\n");
    for i in 0..2 {
        let start = i * 16;
        let end = start + 16;
        let chunk = &sig_r[start..end];
        let mut hex_parts = Vec::new();
        for byte in chunk {
            hex_parts.push(format!("0x{:02x}", byte));
        }
        result.push_str(&format!("            {},", hex_parts.join(", ")));
        if i < 1 {
            result.push('\n');
        }
    }
    result.push_str("\n        ],\n");
    
    result.push_str("        sig_s: [\n");
    for i in 0..2 {
        let start = i * 16;
        let end = start + 16;
        let chunk = &sig_s[start..end];
        let mut hex_parts = Vec::new();
        for byte in chunk {
            hex_parts.push(format!("0x{:02x}", byte));
        }
        result.push_str(&format!("            {},", hex_parts.join(", ")));
        if i < 1 {
            result.push('\n');
        }
    }
    result.push_str("\n        ],\n");
    
    result
}

#[test]
fn test_print_message_hash_for_signing() {
    let e = Env::default();
    // Generate addresses in same order as tests (Env::default() is deterministic)
    let admin = Address::generate(&e);       // 1st (mint signer, Chip 2 mint signer)
    let claimant = Address::generate(&e);    // 2nd (claim/transfer signer)
    let addr_3rd = Address::generate(&e);   // 3rd (claimant2 in test_multiple_chips)

    std::println!("\n=== Message Hashes for Signing (message || signer || nonce) ===\n");
    std::println!("Message: 'test message for minting'");
    std::println!();

    // Hash 1: Chip 1 mint (admin, nonce 1)
    print_message_hash_for_signing_with_signer(
        &e,
        TEST_MESSAGE,
        &admin,
        1,
        "Hash 1 - Chip 1, nonce 1 (mint): sign with Chip 1",
    );
    // Hash 2: Chip 1 claim (claimant = 2nd addr, nonce 2)
    print_message_hash_for_signing_with_signer(
        &e,
        TEST_MESSAGE,
        &claimant,
        2,
        "Hash 2 - Chip 1, nonce 2 (claim): sign with Chip 1",
    );
    // Hash 3: Chip 1 transfer (claimant, nonce 3)
    print_message_hash_for_signing_with_signer(
        &e,
        TEST_MESSAGE,
        &claimant,
        3,
        "Hash 3 - Chip 1, nonce 3 (transfer): sign with Chip 1",
    );
    // Hash 4: Chip 2 mint (admin, nonce 3)
    print_message_hash_for_signing_with_signer(
        &e,
        TEST_MESSAGE,
        &admin,
        3,
        "Hash 4 - Chip 2, nonce 3 (mint): sign with Chip 2",
    );
    // Hash 5: Chip 2 claim (3rd addr = claimant2 in test_multiple_chips, nonce 4)
    print_message_hash_for_signing_with_signer(
        &e,
        TEST_MESSAGE,
        &addr_3rd,
        4,
        "Hash 5 - Chip 2, nonce 4 (claim): sign with Chip 2",
    );

    std::println!("=== End of Message Hashes ===\n");
    std::println!("Sign each message_hash above with the indicated chip:");
    std::println!("  uv run --with blocksec2go blocksec2go generate_signature <key_id> <message_hash>");
    std::println!("Return the DER signature (hex) for each; they will be parsed and formatted for TEST_SIGNATURES.");
    std::println!();

    assert!(true);
}

fn create_client<'a>(e: &Env, admin: &Address) -> NFCtoNFTClient<'a> {
    let address = e.register(
        NFCtoNFT,
        (
            admin,
            &String::from_str(e, "TestNFT"),
            &String::from_str(e, "TNFT"),
            &String::from_str(e, "ipfs://abcd"),
            &10_000u32, // max_tokens
        ),
    );
    NFCtoNFTClient::new(e, &address)
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

    // Chip 1, nonce 1 (mint)
    let mint_sig = &TEST_SIGNATURES[0];
    let mint_message_hash = calculate_message_hash(&e, mint_sig.message, &admin, mint_sig.nonce);
    let (mint_signature, mint_recovery_id) = create_test_signature_and_recovery_id(&e, &mint_message_hash, mint_sig);
    let message = Bytes::from_slice(&e, mint_sig.message);
    let public_key = BytesN::from_array(&e, &mint_sig.public_key);

    let token_id = client.mint(&message, &mint_signature, &mint_recovery_id, &public_key, &mint_sig.nonce);
    assert_eq!(token_id, 0u32);

    // Verify token is unclaimed after mint
    let owner_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        client.owner_of(&token_id)
    }));
    assert!(owner_result.is_err(), "Token should be unclaimed after mint");

    // Chip 1, nonce 2 (claim)
    let claim_sig = &TEST_SIGNATURES[1];
    let claim_message_hash = calculate_message_hash(&e, claim_sig.message, &claimant, claim_sig.nonce);
    let (claim_signature, claim_recovery_id) = create_test_signature_and_recovery_id(&e, &claim_message_hash, claim_sig);
    let message = Bytes::from_slice(&e, claim_sig.message);

    // Claim the token
    let claimed_token_id = client.claim(&claimant, &message, &claim_signature, &claim_recovery_id, &public_key, &claim_sig.nonce);
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

    // Chip 1, nonce 1
    let sig = &TEST_SIGNATURES[0];
    let message_hash = calculate_message_hash(&e, sig.message, &admin, sig.nonce);
    let (signature, recovery_id) = create_test_signature_and_recovery_id(&e, &message_hash, sig);
    let message = Bytes::from_slice(&e, sig.message);
    let public_key = BytesN::from_array(&e, &sig.public_key);

    // First mint should succeed
    let _token_id = client.mint(&message, &signature, &recovery_id, &public_key, &sig.nonce);

    // Second mint with same nonce should panic (nonce reuse prevention)
    client.mint(&message, &signature, &recovery_id, &public_key, &sig.nonce);
}

#[test]
fn test_u64_to_decimal_bytes() {
    let e = Env::default();

    let test_cases: &[(u32, &str)] = &[
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
        let result = crate::contract::u32_to_decimal_bytes(&e, *value);
        assert_eq!(result, Bytes::from_slice(&e, expected_str.as_bytes()));
    }
}

#[test]
fn test_transfer() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let claimant = Address::generate(&e);
    let recipient = Address::generate(&e);
    let client = create_client(&e, &admin);

    // Chip 1, nonce 1 (mint)
    let mint_sig = &TEST_SIGNATURES[0];
    let mint_message_hash = calculate_message_hash(&e, mint_sig.message, &admin, mint_sig.nonce);
    let (mint_signature, mint_recovery_id) = create_test_signature_and_recovery_id(&e, &mint_message_hash, mint_sig);
    let message = Bytes::from_slice(&e, mint_sig.message);
    let public_key = BytesN::from_array(&e, &mint_sig.public_key);
    let token_id = client.mint(&message, &mint_signature, &mint_recovery_id, &public_key, &mint_sig.nonce);
    assert_eq!(token_id, 0u32);

    // Chip 1, nonce 2 (claim)
    let claim_sig = &TEST_SIGNATURES[1];
    let claim_message_hash = calculate_message_hash(&e, claim_sig.message, &claimant, claim_sig.nonce);
    let (claim_signature, claim_recovery_id) = create_test_signature_and_recovery_id(&e, &claim_message_hash, claim_sig);
    let message = Bytes::from_slice(&e, claim_sig.message);
    let claimed_token_id = client.claim(&claimant, &message, &claim_signature, &claim_recovery_id, &public_key, &claim_sig.nonce);
    assert_eq!(claimed_token_id, token_id);

    // Verify initial ownership and balance
    let owner = client.owner_of(&token_id);
    assert_eq!(owner, claimant);
    let claimant_balance_before = client.balance(&claimant);
    assert_eq!(claimant_balance_before, 1u32);
    let recipient_balance_before = client.balance(&recipient);
    assert_eq!(recipient_balance_before, 0u32);

    // Chip 1, nonce 3 (transfer)
    let transfer_sig = &TEST_SIGNATURES[2];
    let transfer_message_hash = calculate_message_hash(&e, transfer_sig.message, &claimant, transfer_sig.nonce);
    let (transfer_signature, transfer_recovery_id) = create_test_signature_and_recovery_id(&e, &transfer_message_hash, transfer_sig);
    let message = Bytes::from_slice(&e, transfer_sig.message);
    client.transfer(&claimant, &recipient, &token_id, &message, &transfer_signature, &transfer_recovery_id, &public_key, &transfer_sig.nonce);

    // Verify ownership changed
    let new_owner = client.owner_of(&token_id);
    assert_eq!(new_owner, recipient, "Token should be owned by recipient after transfer");

    // Verify balances updated
    let claimant_balance_after = client.balance(&claimant);
    assert_eq!(claimant_balance_after, 0u32, "Claimant balance should be 0 after transfer");
    let recipient_balance_after = client.balance(&recipient);
    assert_eq!(recipient_balance_after, 1u32, "Recipient balance should be 1 after transfer");
}

#[test]
fn test_multiple_chips_and_nfts() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let claimant1 = Address::generate(&e);
    let claimant2 = Address::generate(&e);
    let client = create_client(&e, &admin);

    // Chip 1: Mint NFT 1 (nonce 1) and claim it (nonce 2)
    let mint1_sig = &TEST_SIGNATURES[0];
    let mint1_message_hash = calculate_message_hash(&e, mint1_sig.message, &admin, mint1_sig.nonce);
    let (mint1_signature, mint1_recovery_id) = create_test_signature_and_recovery_id(&e, &mint1_message_hash, mint1_sig);
    let message = Bytes::from_slice(&e, mint1_sig.message);
    let public_key_1 = BytesN::from_array(&e, &mint1_sig.public_key);
    let token_id_1 = client.mint(&message, &mint1_signature, &mint1_recovery_id, &public_key_1, &mint1_sig.nonce);
    assert_eq!(token_id_1, 0u32);

    let claim1_sig = &TEST_SIGNATURES[1];
    let claim1_message_hash = calculate_message_hash(&e, claim1_sig.message, &claimant1, claim1_sig.nonce);
    let (claim1_signature, claim1_recovery_id) = create_test_signature_and_recovery_id(&e, &claim1_message_hash, claim1_sig);
    let message = Bytes::from_slice(&e, claim1_sig.message);
    let claimed_token_id_1 = client.claim(&claimant1, &message, &claim1_signature, &claim1_recovery_id, &public_key_1, &claim1_sig.nonce);
    assert_eq!(claimed_token_id_1, token_id_1);

    // Chip 2: Mint NFT 2 (nonce 3) and claim it (nonce 4)
    let mint2_sig = &TEST_SIGNATURES[3];
    let mint2_message_hash = calculate_message_hash(&e, mint2_sig.message, &admin, mint2_sig.nonce);
    let (mint2_signature, mint2_recovery_id) = create_test_signature_and_recovery_id(&e, &mint2_message_hash, mint2_sig);
    let message = Bytes::from_slice(&e, mint2_sig.message);
    let public_key_2 = BytesN::from_array(&e, &mint2_sig.public_key);
    let token_id_2 = client.mint(&message, &mint2_signature, &mint2_recovery_id, &public_key_2, &mint2_sig.nonce);
    assert_eq!(token_id_2, 1u32, "Second token should have ID 1");

    let claim2_sig = &TEST_SIGNATURES[4];
    let claim2_message_hash = calculate_message_hash(&e, claim2_sig.message, &claimant2, claim2_sig.nonce);
    let (claim2_signature, claim2_recovery_id) = create_test_signature_and_recovery_id(&e, &claim2_message_hash, claim2_sig);
    let message = Bytes::from_slice(&e, claim2_sig.message);
    let claimed_token_id_2 = client.claim(&claimant2, &message, &claim2_signature, &claim2_recovery_id, &public_key_2, &claim2_sig.nonce);
    assert_eq!(claimed_token_id_2, token_id_2);

    // Verify both NFTs exist independently
    let owner1 = client.owner_of(&token_id_1);
    assert_eq!(owner1, claimant1, "NFT 1 should be owned by claimant1");
    
    let owner2 = client.owner_of(&token_id_2);
    assert_eq!(owner2, claimant2, "NFT 2 should be owned by claimant2");

    // Verify both public keys are stored correctly
    let stored_public_key_1 = client.public_key(&token_id_1);
    assert_eq!(stored_public_key_1, public_key_1, "NFT 1 should have Chip 1's public key");
    
    let stored_public_key_2 = client.public_key(&token_id_2);
    assert_eq!(stored_public_key_2, public_key_2, "NFT 2 should have Chip 2's public key");

    // Verify token IDs are mapped correctly
    let stored_token_id_1 = client.token_id(&public_key_1);
    assert_eq!(stored_token_id_1, token_id_1, "Chip 1's public key should map to token ID 1");
    
    let stored_token_id_2 = client.token_id(&public_key_2);
    assert_eq!(stored_token_id_2, token_id_2, "Chip 2's public key should map to token ID 2");

    // Verify balances are tracked separately
    let balance1 = client.balance(&claimant1);
    assert_eq!(balance1, 1u32, "Claimant1 should have balance of 1");
    
    let balance2 = client.balance(&claimant2);
    assert_eq!(balance2, 1u32, "Claimant2 should have balance of 1");

    // Verify token URIs are different
    let uri1 = client.token_uri(&token_id_1);
    let uri2 = client.token_uri(&token_id_2);
    assert_eq!(uri1, String::from_str(&e, "ipfs://abcd/0"));
    assert_eq!(uri2, String::from_str(&e, "ipfs://abcd/1"));
}


