//! `CustomAccountInterface` for Pocket.
//!
//! The chip signs the host-computed authorization payload —
//! `sha256(HashIdPreimage::SorobanAuthorization { network_id, nonce,
//! signature_expiration_ledger, invocation })` — binding, replay and expiry are all
//! host-enforced, so this contract keeps no nonce of its own.
//!
//! Verification is **linked, not delegated**. [`chimpdao_chip_auth`] is the single
//! implementation of both chip algorithms and is called directly against the key and
//! curve stored at construction. An earlier revision cross-called the NFT registry
//! instead, which meant a stored contract address decided whether a signature was
//! valid — so whoever could re-point that address could authorize anything, and every
//! purse depended on that registry staying alive. Neither is true now.

use soroban_sdk::auth::{Context, CustomAccountInterface};
use soroban_sdk::crypto::Hash;
use soroban_sdk::{BytesN, Env, Vec, contractimpl};

use crate::errors::PocketError;
use crate::types;
use crate::{Pocket, PocketArgs, PocketClient};

#[contractimpl]
impl CustomAccountInterface for Pocket {
    type Signature = types::ChipAuth;
    type Error = PocketError;

    fn __check_auth(
        e: Env,
        signature_payload: Hash<32>,
        signature: types::ChipAuth,
        // Unused on purpose: the bound chip is the sole authority over this purse, so
        // there is no per-context policy to apply. Not matching on `Context` also keeps
        // us forward-compatible with CAP-85, which adds a `ContractExecutable` variant.
        _auth_contexts: Vec<Context>,
    ) -> Result<(), PocketError> {
        let public_key: BytesN<65> = e
            .storage()
            .instance()
            .get(&types::DataKey::Chip)
            .ok_or(PocketError::InvalidChip)?;
        let curve: types::Curve = e
            .storage()
            .instance()
            .get(&types::DataKey::Curve)
            .ok_or(PocketError::InvalidChip)?;

        if !chimpdao_chip_auth::verify_chip_auth(
            &e,
            &signature_payload,
            &public_key,
            &curve,
            signature,
        ) {
            return Err(PocketError::InvalidSignature);
        }
        Ok(())
    }
}
