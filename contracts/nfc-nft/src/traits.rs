//! Dynamic NFT traits (**ERC-7496**), plus the pointer from a card to its purse.
//!
//! ERC-7496 is an Ethereum ERC, not a SEP — no SEP defines NFT traits, and SEP-50 covers
//! only the token itself. The shape is therefore Ethereum's: `trait_value` /
//! `trait_values` / `set_trait` / `trait_metadata_uri`, described off-chain by
//! `metadata.json`.
//!
//! **Every trait here is stored, and that is a rule rather than a coincidence.** The
//! standard requires each trait change to be an explicit on-chain action that emits an
//! event, so an indexer stays in sync by replaying events instead of polling. A trait
//! computed live from another contract can never honour that: it changes inside a
//! contract that has never heard of this NFT, so nothing is emitted and every cached
//! copy is wrong from the card's next payment onward.
//!
//! So a card's **money is not a trait**. [`NFCtoNFT::pocket`] hands out the purse
//! address and the purse answers for itself — which is also the only honest answer,
//! since the purse holds assets this contract has no list of, on chains it cannot see,
//! and its own `balance` is whatever wasm the holder last chose to run.

use crate::contract::{DataKey, NFTStorageKey};
use crate::{NFCtoNFT, NFCtoNFTArgs, NFCtoNFTClient, NFCtoNFTTrait, errors, events};
use soroban_sdk::{
    Address, Env, IntoVal, InvokeError, String, Symbol, Vec, contractimpl, panic_with_error, vec,
};

/// The card's rank, which drives its art. Stored, admin-set, and the only trait.
pub const TRAIT_TIER: &str = "tier";

/// Ceiling on one `trait_values` batch. A view is free to whoever simulates it, so the
/// convenience helper must not also be a way to multiply work for nothing.
const MAX_TRAIT_KEYS: u32 = 32;

#[contractimpl]
impl NFCtoNFT {
    /// Value of one trait, or `0` for a known trait that has never been set — the
    /// standard's default. An unknown key is an error, not a zero.
    pub fn trait_value(e: &Env, token_id: u32, trait_key: String) -> i128 {
        // Existence check first, so an unknown token fails the same way everywhere.
        Self::public_key(e, token_id);

        if trait_key == String::from_str(e, TRAIT_TIER) {
            return e
                .storage()
                .persistent()
                .get(&NFTStorageKey::Tier(token_id))
                .unwrap_or(0i128);
        }
        panic_with_error!(e, errors::NonFungibleTokenError::TraitDoesNotExist)
    }

    pub fn trait_values(e: &Env, token_id: u32, trait_keys: Vec<String>) -> Vec<i128> {
        if trait_keys.len() > MAX_TRAIT_KEYS {
            panic_with_error!(e, errors::NonFungibleTokenError::TooManyTraitKeys);
        }
        let mut out = Vec::new(e);
        for key in trait_keys.iter() {
            out.push_back(Self::trait_value(e, token_id, key));
        }
        out
    }

    pub fn set_trait(e: &Env, token_id: u32, trait_key: String, new_value: i128) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        Self::public_key(e, token_id);

        if trait_key != String::from_str(e, TRAIT_TIER) {
            panic_with_error!(e, errors::NonFungibleTokenError::TraitDoesNotExist);
        }
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Tier(token_id), &new_value);

        events::SetTrait {
            trait_key,
            token_id,
            new_value,
        }
        .publish(e);
    }

    /// Where the ERC-7496 trait schema lives.
    pub fn trait_metadata_uri(e: &Env) -> String {
        e.storage()
            .instance()
            .get(&DataKey::TraitUri)
            .unwrap_or_else(|| String::from_str(e, ""))
    }

    /// Admin-set, so the schema can be republished without an upgrade. Emits, because
    /// the schema is what tells a reader how to interpret every value it has cached.
    pub fn set_trait_metadata_uri(e: &Env, uri: String) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.storage().instance().set(&DataKey::TraitUri, &uri);
        events::TraitMetadataUri { uri }.publish(e);
    }

    /// This card's purse, or `None` when no factory is configured or no purse has been
    /// deployed yet.
    ///
    /// The one link an outside reader cannot reconstruct alone: `public_key(token_id)`
    /// is public, but nothing on chain says which factory to ask. Deliberately a
    /// *pointer* and not a balance — the purse holds the card's float and its DeFi
    /// positions, and it can answer for both without this contract mirroring either.
    ///
    /// Best-effort by design: a missing, mis-pointed or trapping factory reads as
    /// `None`. Resolving a card must never be able to fail because of a contract this
    /// one merely points at.
    pub fn pocket(e: &Env, token_id: u32) -> Option<Address> {
        let public_key = Self::public_key(e, token_id);
        let factory: Address = e.storage().instance().get(&DataKey::Factory)?;
        match e.try_invoke_contract::<Option<Address>, InvokeError>(
            &factory,
            &Symbol::new(e, "get_account"),
            vec![e, public_key.into_val(e)],
        ) {
            Ok(Ok(found)) => found,
            _ => None,
        }
    }
}
