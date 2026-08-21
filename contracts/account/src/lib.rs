//! The Chimp account — the durable root a holder's cards belong to.
//!
//! Cards are the signers, one signature is enough (1-of-n), and the card's 65-byte SEC1
//! public key **is** its identity. There is no rule/policy layer: the account holds a
//! flat set of cards, so there are no rule ids to allocate, bind into a digest, go
//! sparse, or accidentally delete a co-signer with.
//!
//! The chip signs the payload the **host** computes —
//! `sha256(HashIdPreimage::SorobanAuthorization { network_id, nonce,
//! signature_expiration_ledger, invocation })` — so binding, replay and expiry are all
//! host-enforced and this contract keeps no nonce. That is the same payload
//! `contracts/pocket` signs; only the envelope differs, because here the signature must
//! also say *which* card produced it.
//!
//! Verification is linked, not delegated: [`chimpdao_chip_auth`] is the one
//! implementation of both chip algorithms, and calling it directly means no stored
//! verifier address that a departing holder could re-point.

#![no_std]

use soroban_sdk::auth::{Context, CustomAccountInterface};
use soroban_sdk::crypto::Hash;
use soroban_sdk::{
    BytesN, Env, Vec, contract, contractimpl, contractmeta, contracttype, panic_with_error,
};

use chimpdao_chip_auth::{ChipAuth, Curve};

mod errors;
mod events;
#[cfg(test)]
mod test;

pub use errors::AccountError;

contractmeta!(
    key = "Description",
    val = "ChimpDAO account (cards are the signers)"
);

/// One card authorized on this account. The curve is recorded here so `__check_auth`
/// needs no external lookup — a card cannot change algorithm.
#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CardSigner {
    pub key: BytesN<65>,
    pub curve: Curve,
}

/// What a card presents to authorize a call: which card, and its signature over the
/// host payload. `key` selects the signer; it is not trusted beyond that — the
/// signature must verify against the *stored* entry for that key.
#[contracttype]
#[derive(Clone)]
pub struct AccountAuth {
    pub key: BytesN<65>,
    pub auth: ChipAuth,
}

#[contracttype]
pub enum DataKey {
    /// `Vec<CardSigner>`. Its own key so a future `Passkeys` set can be added without
    /// migrating anything.
    Cards,
}

#[contract]
pub struct ChimpAccount;

fn cards(e: &Env) -> Vec<CardSigner> {
    e.storage()
        .instance()
        .get(&DataKey::Cards)
        .unwrap_or_else(|| Vec::new(e))
}

fn put_cards(e: &Env, cards: &Vec<CardSigner>) {
    e.storage().instance().set(&DataKey::Cards, cards);
}

/// Signer-management and upgrades are authorized by the account itself, which routes
/// back through `__check_auth` — i.e. any card already on the account consents.
fn require_self(e: &Env) {
    e.current_contract_address().require_auth();
}

#[contractimpl]
impl ChimpAccount {
    /// Founding cards. Normally exactly one; the factory seeds it with the card that
    /// created the account.
    pub fn __constructor(e: &Env, cards: Vec<CardSigner>) {
        if cards.is_empty() {
            panic_with_error!(e, AccountError::NoCards);
        }
        put_cards(e, &cards);
    }

    /// Add a card. Authorized by a card already on the account.
    pub fn add_card(e: &Env, card: CardSigner) {
        require_self(e);
        let mut current = cards(e);
        if current.iter().any(|c| c.key == card.key) {
            panic_with_error!(e, AccountError::DuplicateCard);
        }
        current.push_back(card.clone());
        put_cards(e, &current);
        events::CardAdded { key: card.key }.publish(e);
    }

    /// Remove a card, refusing to remove the last one — an account with no signer can
    /// never authorize anything again, including adding a signer back. Deliberately
    /// emptying the account is [`ChimpAccount::abandon`].
    pub fn remove_card(e: &Env, key: BytesN<65>) {
        require_self(e);
        let current = cards(e);
        if current.len() <= 1 {
            panic_with_error!(e, AccountError::LastCard);
        }
        let mut kept = Vec::new(e);
        for c in current.iter() {
            if c.key != key {
                kept.push_back(c);
            }
        }
        if kept.len() == current.len() {
            panic_with_error!(e, AccountError::UnknownCard);
        }
        put_cards(e, &kept);
        events::CardRemoved { key }.publish(e);
    }

    /// Give up the account: remove its final card. Separate from `remove_card` so the
    /// unrecoverable case is always an explicit choice — this is the sole-card handover,
    /// where the account is being left behind on purpose.
    pub fn abandon(e: &Env) {
        require_self(e);
        put_cards(e, &Vec::new(e));
        events::Abandoned {}.publish(e);
    }

    /// Every card authorized on this account.
    pub fn cards(e: &Env) -> Vec<CardSigner> {
        cards(e)
    }

    /// Whether this card can sign for this account. The soulbound check nfc-nft makes.
    pub fn has_card(e: &Env, key: BytesN<65>) -> bool {
        cards(e).iter().any(|c| c.key == key)
    }

    /// Replace this account's wasm. Card-authorized, like every other mutation.
    pub fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        require_self(e);
        e.deployer().update_current_contract_wasm(wasm_hash);
    }
}

#[contractimpl]
impl CustomAccountInterface for ChimpAccount {
    type Signature = AccountAuth;
    type Error = AccountError;

    fn __check_auth(
        e: Env,
        signature_payload: Hash<32>,
        signature: AccountAuth,
        // Unused on purpose: any card on the account may authorize any context (1-of-n).
        // Not matching on `Context` also keeps us forward-compatible with CAP-85, which
        // adds a `ContractExecutable` variant.
        _auth_contexts: Vec<Context>,
    ) -> Result<(), AccountError> {
        let card = cards(&e)
            .iter()
            .find(|c| c.key == signature.key)
            .ok_or(AccountError::UnknownCard)?;

        if !chimpdao_chip_auth::verify_chip_auth(
            &e,
            &signature_payload,
            &card.key,
            &card.curve,
            signature.auth,
        ) {
            return Err(AccountError::InvalidSignature);
        }
        Ok(())
    }
}
