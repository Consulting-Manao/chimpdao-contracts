use crate::types::{ChipAuth, Curve, Secp256k1Auth, Secp256r1Auth};
use soroban_sdk::crypto::Hash;
use soroban_sdk::xdr::ToXdr;
use soroban_sdk::{Bytes, BytesN, Env};

/// `sha256(message ‖ signer ‖ nonce_xdr)` — Pocket / nfc-nft digest.
pub fn message_digest(e: &Env, message: &Bytes, signer: &Bytes, nonce: u32) -> Hash<32> {
    let mut builder = Bytes::new(e);
    builder.append(message);
    builder.append(signer);
    builder.append(&nonce.to_xdr(e));
    e.crypto().sha256(&builder)
}

/// IntAuth signed payload: `F0 F0 ‖ 80 00 ‖ RndB(16) ‖ challenge(16)`.
/// Challenge is the first 16 bytes of the 32-byte digest (DUOX).
fn int_auth_signed_bytes(e: &Env, digest: &Hash<32>, rnd_b: &BytesN<16>) -> Bytes {
    let hash_bytes: Bytes = digest.clone().into();
    let mut signed = Bytes::new(e);
    signed.extend_from_array(&[0xf0, 0xf0, 0x80, 0x00]);
    signed.append(&Bytes::from(rnd_b.clone()));
    for i in 0..16 {
        signed.push_back(hash_bytes.get(i).unwrap());
    }
    signed
}

fn verify_k1(e: &Env, digest: &Hash<32>, public_key: &BytesN<65>, a: Secp256k1Auth) -> bool {
    let recovered = e
        .crypto()
        .secp256k1_recover(digest, &a.signature, a.recovery_id);
    recovered == *public_key
}

fn verify_r1(e: &Env, digest: &Hash<32>, public_key: &BytesN<65>, a: Secp256r1Auth) -> bool {
    let signed = int_auth_signed_bytes(e, digest, &a.rnd_b);
    let payload_hash = e.crypto().sha256(&signed);
    e.crypto()
        .secp256r1_verify(public_key, &payload_hash, &a.signature);
    true
}

/// Verify k1 recover or r1 IntAuth against `public_key` for a 32-byte digest.
/// Returns false on k1 mismatch or curve/auth mismatch; r1 traps on bad sig (host).
pub fn verify_chip_auth(
    e: &Env,
    message_digest: &Hash<32>,
    public_key: &BytesN<65>,
    curve: &Curve,
    auth: ChipAuth,
) -> bool {
    match (curve, auth) {
        (Curve::Secp256k1, ChipAuth::Secp256k1(a)) => verify_k1(e, message_digest, public_key, a),
        (Curve::Secp256r1, ChipAuth::Secp256r1(a)) => verify_r1(e, message_digest, public_key, a),
        _ => false,
    }
}

/// OZ Verifier passes a bare 32-byte digest as `Bytes`, not `Hash`.
/// `Hash` is `repr(transparent)` over `BytesN<32>`; wrap so we can use stable
/// `Crypto::secp256k1_recover` (no `crypto_hazmat` / hazmat-crypto feature).
///
/// ponytail: ceiling = relies on Hash layout; upgrade if SDK exposes a stable
/// Bytes→Hash for prehashed digests (OZ Verifier path).
fn hash_from_digest_bytes(e: &Env, digest_bytes: &Bytes) -> Option<Hash<32>> {
    if digest_bytes.len() < 32 {
        return None;
    }
    let mut arr = [0u8; 32];
    for i in 0..32 {
        arr[i as usize] = digest_bytes.get(i).unwrap();
    }
    let bn = BytesN::<32>::from_array(e, &arr);
    Some(unsafe { core::mem::transmute::<BytesN<32>, Hash<32>>(bn) })
}

/// Crypto-only verify for a raw 32-byte digest (OZ Verifier / Earn path).
/// Curve is implied by the `ChipAuth` variant (OZ has no separate Curve arg).
pub fn verify_digest_bytes(
    e: &Env,
    digest_bytes: &Bytes,
    public_key: &BytesN<65>,
    auth: ChipAuth,
) -> bool {
    let Some(digest) = hash_from_digest_bytes(e, digest_bytes) else {
        return false;
    };
    match auth {
        ChipAuth::Secp256k1(a) => verify_k1(e, &digest, public_key, a),
        ChipAuth::Secp256r1(a) => verify_r1(e, &digest, public_key, a),
    }
}

#[cfg(test)]
mod tests {
    use super::int_auth_signed_bytes;
    use soroban_sdk::{BytesN, Env};

    // ponytail: layout-only SoT check — live Infineon/DUOX is the real crypto test.
    #[test]
    fn int_auth_packing_is_36_bytes() {
        let e = Env::default();
        let digest = e.crypto().sha256(&soroban_sdk::Bytes::from_slice(&e, b"probe"));
        let rnd = BytesN::<16>::from_array(&e, &[0xab; 16]);
        let signed = int_auth_signed_bytes(&e, &digest, &rnd);
        assert_eq!(signed.len(), 36);
        assert_eq!(signed.get(0).unwrap(), 0xf0);
        assert_eq!(signed.get(1).unwrap(), 0xf0);
        assert_eq!(signed.get(2).unwrap(), 0x80);
        assert_eq!(signed.get(3).unwrap(), 0x00);
        assert_eq!(signed.get(4).unwrap(), 0xab);
        assert_eq!(signed.get(19).unwrap(), 0xab);
    }
}
