//! Nido `Verifier` for Infineon secp256k1 + DUOX secp256r1 IntAuth chip signatures.
//!
//! Stateless by design (OZ Verifier = crypto oracle). Replay for Earn lives in Soroban auth
//! nonce + OZ auth_digest (signature_payload ‖ context_rule_ids). Pocket ChipAuth keeps its
//! own monotonic nonce — do not add app nonce here.
//!
//! Crypto body lives in `chimpdao-chip-auth` (shared with Pocket / nfc-nft).

use chimpdao_chip_auth::{ChipAuth, Secp256k1Auth, Secp256r1Auth};
use soroban_sdk::{contract, contractimpl, xdr::FromXdr, Bytes, BytesN, Env, Vec};
use stellar_accounts::verifiers::{utils::extract_from_bytes, Verifier};

/// Soft cap — Nido batch canonicalize should stay small.
const MAX_BATCH_KEYS: u32 = 32;

#[contract]
pub struct ChipVerifier;

/// Earn AuthPayload XDR names (same layout as ChipAuth).
pub type ChipSigData = ChipAuth;
pub type Secp256k1Sig = Secp256k1Auth;
pub type Secp256r1Sig = Secp256r1Auth;

#[contractimpl]
impl Verifier for ChipVerifier {
    type KeyData = Bytes;
    type SigData = Bytes;

    fn verify(e: &Env, signature_payload: Bytes, key_data: Bytes, sig_data: Bytes) -> bool {
        let pub_key: BytesN<65> =
            extract_from_bytes(e, &key_data, 0..65).expect("65-byte SEC1 public key");

        let Ok(auth) = ChipAuth::from_xdr(e, &sig_data) else {
            return false;
        };

        // OZ passes the 32-byte auth digest as Bytes.
        chimpdao_chip_auth::verify_digest_bytes(e, &signature_payload, &pub_key, auth)
    }

    fn canonicalize_key(e: &Env, key_data: Bytes) -> Bytes {
        let pub_key: BytesN<65> =
            extract_from_bytes(e, &key_data, 0..65).expect("65-byte SEC1 public key");
        pub_key.into()
    }

    fn batch_canonicalize_key(e: &Env, key_data: Vec<Bytes>) -> Vec<Bytes> {
        assert!(
            key_data.len() <= MAX_BATCH_KEYS,
            "batch_canonicalize_key: too many keys"
        );
        let mut out = Vec::new(e);
        for k in key_data.iter() {
            out.push_back(Self::canonicalize_key(e, k));
        }
        out
    }
}
