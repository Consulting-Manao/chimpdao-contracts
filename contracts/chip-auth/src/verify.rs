use crate::types::{ChipAuth, Curve, Secp256k1Auth, Secp256r1Auth};
#[allow(deprecated)]
use soroban_sdk::TryFromValForContractFn;
use soroban_sdk::crypto::Hash;
use soroban_sdk::xdr::ToXdr;
use soroban_sdk::{Address, Bytes, BytesN, Env, Symbol, Val, Vec};

/// `sha256(domain ‖ contract_xdr ‖ fn_name_xdr ‖ args_xdr ‖ nonce_xdr)` — a chip
/// *presence attestation* good for exactly one call, once. `domain` must be distinct per
/// contract so a signature cannot be carried between them.
///
/// For contracts where the chip is a second factor beside a wallet (`nfc-nft`). Where the
/// chip **is** the account (Pocket), use `CustomAccountInterface` and let the host build
/// the payload instead.
pub fn call_digest(
    e: &Env,
    domain: &[u8],
    contract: &Address,
    fn_name: &Symbol,
    args: &Vec<Val>,
    nonce: u32,
) -> Hash<32> {
    let mut builder = Bytes::new(e);
    builder.extend_from_slice(domain);
    builder.append(&contract.to_xdr(e));
    builder.append(&fn_name.to_xdr(e));
    // Whole-Vec XDR: args are length-delimited as a unit, so they cannot be re-partitioned.
    builder.append(&args.to_xdr(e));
    builder.append(&nonce.to_xdr(e));
    e.crypto().sha256(&builder)
}

/// IntAuth signed payload: `F0 F0 ‖ 80 00 ‖ RndB(16) ‖ challenge(16)`.
/// Challenge is the first 16 bytes of the 32-byte digest (DUOX).
///
/// ponytail: ceiling = IntAuth carries only 16 bytes, so an r1 signature commits to
/// `digest[0..16]`. A chosen-digest adversary needs 2^64, not 2^128 — prefer k1 for
/// high-value rules. Hardware limit; not fixable here.
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

/// `secp256r1_verify` has no fallible form: this returns `true` or traps, where
/// [`verify_k1`] returns `false`. Fail-closed either way, but a multi-signer rule gets no
/// chance to try the next signer after an r1 failure.
fn verify_r1(e: &Env, digest: &Hash<32>, public_key: &BytesN<65>, a: Secp256r1Auth) -> bool {
    let signed = int_auth_signed_bytes(e, digest, &a.rnd_b);
    let payload_hash = e.crypto().sha256(&signed);
    e.crypto()
        .secp256r1_verify(public_key, &payload_hash, &a.signature);
    true
}

/// Verify k1 recover or r1 IntAuth against `public_key` for a 32-byte digest.
///
/// Returns false on k1 mismatch or curve/auth mismatch. **r1 traps rather than
/// returning false** — see [`verify_r1`].
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

/// OZ `Verifier` hands over a bare 32-byte digest as `Bytes`, but the stable crypto entry
/// points take `Hash<32>`, which has no public constructor. `TryFromValForContractFn` is
/// how the host materialises one for a call argument — which is what this digest is.
///
/// ponytail: ceiling = trait is deprecated-as-internal, so this pins the SDK version. If
/// it goes without a prehashed-digest replacement, switch the verifier convention to
/// signing `sha256(signature_payload)`.
#[allow(deprecated)]
fn hash_from_digest_bytes(e: &Env, digest_bytes: &Bytes) -> Option<Hash<32>> {
    if digest_bytes.len() != 32 {
        return None;
    }
    let mut arr = [0u8; 32];
    for i in 0..32 {
        arr[i as usize] = digest_bytes.get(i).unwrap();
    }
    let bn = BytesN::<32>::from_array(e, &arr);
    Hash::<32>::try_from_val_for_contract_fn(e, &bn.to_val()).ok()
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
    use super::{call_digest, int_auth_signed_bytes};
    use soroban_sdk::{
        Address, BytesN, Env, IntoVal, String as SString, Symbol, Val, Vec, testutils::Address as _,
    };

    fn digest(e: &Env, fn_name: &str, args: Vec<Val>, nonce: u32, c: &Address) -> [u8; 32] {
        call_digest(e, b"test.domain", c, &Symbol::new(e, fn_name), &args, nonce)
            .to_bytes()
            .to_array()
    }

    /// The property the design rests on: any change to the call changes the digest.
    #[test]
    fn digest_changes_with_every_field() {
        let e = Env::default();
        let c1 = Address::generate(&e);
        let c2 = Address::generate(&e);
        let a1 = Vec::from_array(&e, [1u32.into_val(&e)]);
        let a2 = Vec::from_array(&e, [2u32.into_val(&e)]);

        let base = digest(&e, "act", a1.clone(), 1, &c1);
        assert_ne!(base, digest(&e, "other", a1.clone(), 1, &c1), "fn name");
        assert_ne!(base, digest(&e, "act", a2, 1, &c1), "args");
        assert_ne!(base, digest(&e, "act", a1.clone(), 2, &c1), "nonce");
        assert_ne!(base, digest(&e, "act", a1, 1, &c2), "contract");
    }

    /// SoT for the TypeScript `callDigest` in chimpdao-terminal.
    /// `cargo test -p chimpdao-chip-auth print_cross_client_vector -- --nocapture`
    #[test]
    fn print_cross_client_vector() {
        extern crate std;
        let e = Env::default();
        let contract = Address::from_string(&SString::from_str(
            &e,
            "CDXIJB4UZ6DA7OVFH3HYXUKXB7G6Z2ZD4MG7PTONQ5QELL656KMWCZE4",
        ));
        let claimant = Address::from_string(&SString::from_str(
            &e,
            "GBBD47IF6LWK7P7MDEVSCWR7DPUWV3NY3DTQEVFL4NAT4AQH3ZLLFLA5",
        ));
        let args: Vec<Val> = Vec::from_array(&e, [claimant.into_val(&e)]);
        let d = call_digest(
            &e,
            b"chimpdao.nfc-nft.v2",
            &contract,
            &Symbol::new(&e, "claim"),
            &args,
            7,
        );
        let mut hex = std::string::String::new();
        for b in d.to_bytes().to_array() {
            hex.push_str(&std::format!("{:02x}", b));
        }
        assert_eq!(
            hex, "2b23d024c62e7c8d1d37f118e574ef030ffc7b37efc8bb77439c09b93c97ce7c",
            "TS callDigest in chimpdao-terminal must match"
        );
        std::println!("CLAIM_DIGEST {}", hex);
    }

    /// DUOX IntAuth framing: F0F0 8000 ‖ RndB(16) ‖ digest[0..16].
    #[test]
    fn int_auth_packing_is_36_bytes() {
        let e = Env::default();
        let digest = e
            .crypto()
            .sha256(&soroban_sdk::Bytes::from_slice(&e, b"probe"));
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
