#![cfg(test)]

extern crate std;

use soroban_sdk::{Bytes, BytesN, Env, Vec, xdr::ToXdr};
use stellar_accounts::verifiers::Verifier;

use crate::{ChipSigData, ChipVerifier, Secp256k1Sig};

#[test]
fn canonicalize_key_strips_trailer() {
    let e = Env::default();
    let mut key = [4u8; 80];
    key[0] = 4;
    let key_data = Bytes::from_slice(&e, &key);
    let canon = ChipVerifier::canonicalize_key(&e, key_data);
    assert_eq!(canon.len(), 65);
    for i in 0..65u32 {
        assert_eq!(canon.get(i), Some(key[i as usize]));
    }
}

#[test]
#[should_panic(expected = "65-byte SEC1 public key")]
fn canonicalize_key_rejects_short() {
    let e = Env::default();
    let key_data = Bytes::from_slice(&e, &[4u8; 32]);
    ChipVerifier::canonicalize_key(&e, key_data);
}

#[test]
fn batch_canonicalize_preserves_order() {
    let e = Env::default();
    let a = Bytes::from_slice(&e, &[4u8; 65]);
    let mut b_bytes = [5u8; 70];
    b_bytes[0] = 4;
    let b = Bytes::from_slice(&e, &b_bytes);
    let mut keys = Vec::new(&e);
    keys.push_back(a.clone());
    keys.push_back(b);
    let out = ChipVerifier::batch_canonicalize_key(&e, keys);
    assert_eq!(out.len(), 2);
    assert_eq!(out.get(0).unwrap().len(), 65);
    assert_eq!(out.get(1).unwrap().len(), 65);
    assert_eq!(out.get(0).unwrap().get(1), Some(4));
    assert_eq!(out.get(1).unwrap().get(1), Some(5));
}

#[test]
fn verify_rejects_wrong_payload_len() {
    let e = Env::default();
    let key = Bytes::from_slice(&e, &[4u8; 65]);
    let sig = ChipSigData::Secp256k1(Secp256k1Sig {
        signature: BytesN::from_array(&e, &[1u8; 64]),
        recovery_id: 0,
    });
    let sig_bytes: Bytes = sig.to_xdr(&e);
    let short = Bytes::from_slice(&e, &[0u8; 16]);
    assert!(!ChipVerifier::verify(&e, short, key, sig_bytes));
}

#[test]
fn verify_k1_rejects_junk_sig() {
    let e = Env::default();
    let key = Bytes::from_slice(&e, &[4u8; 65]);
    let sig = ChipSigData::Secp256k1(Secp256k1Sig {
        signature: BytesN::from_array(&e, &[1u8; 64]),
        recovery_id: 0,
    });
    let sig_bytes: Bytes = sig.to_xdr(&e);
    let digest = Bytes::from_slice(&e, &[9u8; 32]);
    assert!(!ChipVerifier::verify(&e, digest, key, sig_bytes));
}

#[test]
#[should_panic(expected = "batch_canonicalize_key: too many keys")]
fn batch_canonicalize_rejects_oversized() {
    let e = Env::default();
    let mut keys = Vec::new(&e);
    for _ in 0..33u32 {
        keys.push_back(Bytes::from_slice(&e, &[4u8; 65]));
    }
    ChipVerifier::batch_canonicalize_key(&e, keys);
}
