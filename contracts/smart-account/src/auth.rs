//! `CustomAccountInterface` for Pocket.
//!
//! The chip signs the host-computed authorization payload —
//! `sha256(HashIdPreimage::SorobanAuthorization { network_id, nonce,
//! signature_expiration_ledger, invocation })` — where `invocation` is the contract,
//! function name, argument `ScVal`s and sub-invocations actually being executed.
//!
//! That is the whole point of this module: the signature is bound to the call by the
//! host, not by a client convention. Replay and expiry are host-enforced too, so this
//! contract keeps no nonce of its own.

use soroban_sdk::auth::{Context, CustomAccountInterface};
use soroban_sdk::crypto::Hash;
use soroban_sdk::{BytesN, Env, Vec, contractimpl};

use crate::errors::SmartAccountError;
use crate::types;
use crate::{SmartAccount, SmartAccountArgs, SmartAccountClient};

#[contractimpl]
impl CustomAccountInterface for SmartAccount {
    type Signature = types::ChipAuth;
    type Error = SmartAccountError;

    fn __check_auth(
        e: Env,
        signature_payload: Hash<32>,
        signature: types::ChipAuth,
        // Unused on purpose: the bound chip is the sole authority over this purse, so
        // there is no per-context policy to apply. Not matching on `Context` also keeps
        // us forward-compatible with CAP-85, which adds a `ContractExecutable` variant.
        _auth_contexts: Vec<Context>,
    ) -> Result<(), SmartAccountError> {
        let public_key: BytesN<65> = e
            .storage()
            .instance()
            .get(&types::DataKey::Chip)
            .ok_or(SmartAccountError::InvalidChip)?;
        let curve: types::Curve = e
            .storage()
            .instance()
            .get(&types::DataKey::Curve)
            .ok_or(SmartAccountError::MissingCurve)?;

        if !chimpdao_chip_auth::verify_chip_auth(
            &e,
            &signature_payload,
            &public_key,
            &curve,
            signature,
        ) {
            return Err(SmartAccountError::InvalidSignature);
        }

        Ok(())
    }
}
