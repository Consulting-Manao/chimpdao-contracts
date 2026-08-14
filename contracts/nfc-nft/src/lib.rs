#![no_std]

//! Physical-backed NFT: one token per physical card.
//!
//! The chip signature is a **presence attestation** beside a wallet's `require_auth`, not
//! the account authority — which is why this verifies chip signatures itself instead of
//! being a `CustomAccountInterface` like Pocket. See [`chimpdao_chip_auth::call_digest`].

use chimpdao_chip_auth::{ChipAuth, Curve};
use soroban_sdk::{Address, BytesN, Env, String, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO NFC-NFT");

mod collection_contract {
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/collection.wasm");
}

mod contract;

mod errors;
mod events;
#[cfg(test)]
mod test;

#[contract]
pub struct NFCtoNFT;

pub trait NFCtoNFTTrait {
    fn __constructor(
        e: &Env,
        admin: Address,
        collection_contract: Address,
        name: String,
        symbol: String,
        uri: String,
        max_tokens: u32,
    );

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// Mint the NFT for a card. Admin authorizes; the chip attests it was present.
    ///
    /// The chip signs `call_digest(DOMAIN, this, "mint", [public_key, curve], nonce)`,
    /// so the signature is good for this mint and nothing else.
    fn mint(e: &Env, auth: ChipAuth, public_key: BytesN<65>, curve: Curve, nonce: u32) -> u32;

    /// Claim the minted NFT to `claimant`.
    ///
    /// Chip signs `call_digest(DOMAIN, this, "claim", [claimant], nonce)`.
    fn claim(e: &Env, claimant: Address, auth: ChipAuth, public_key: BytesN<65>, nonce: u32)
    -> u32;

    /// Transfer a claimed NFT. The card must be present — that is the point of a
    /// physical-backed token.
    ///
    /// Chip signs `call_digest(DOMAIN, this, "transfer", [from, to, token_id], nonce)`.
    fn transfer(
        e: &Env,
        from: Address,
        to: Address,
        token_id: u32,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    );

    fn clawback(e: &Env, token_id: u32);

    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32;

    fn balance(e: &Env, owner: Address) -> u32;

    fn owner_of(e: &Env, token_id: u32) -> Address;

    fn name(e: &Env) -> String;

    fn symbol(e: &Env) -> String;

    fn token_uri(e: &Env, token_id: u32) -> String;

    fn token_id(e: &Env, public_key: BytesN<65>) -> u32;

    fn next_token_id(e: &Env) -> u32;

    fn public_key(e: &Env, token_id: u32) -> BytesN<65>;

    /// Curve recorded for a chip at mint. Integrators verifying chip signatures in
    /// their own contracts need this alongside [`NFCtoNFTTrait::public_key`].
    fn curve(e: &Env, public_key: BytesN<65>) -> Curve;
}
