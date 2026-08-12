#![no_std]

use chimpdao_chip_auth::{ChipAuth, Curve};
use soroban_sdk::{Address, Bytes, BytesN, Env, String, contract, contractmeta};

contractmeta!(key = "Description", val = "ChimpDAO NFC-NFT");

mod collection_contract {
    soroban_sdk::contractimport!(file = "../collection.wasm");
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

    /// Mint NFT for a chip. Admin + ChipAuth (k1 or r1). Stores curve with the chip.
    fn mint(
        e: &Env,
        message: Bytes,
        auth: ChipAuth,
        public_key: BytesN<65>,
        curve: Curve,
        nonce: u32,
    ) -> u32;

    /// Claim minted NFT to `claimant` with ChipAuth.
    fn claim(
        e: &Env,
        claimant: Address,
        message: Bytes,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u32;

    /// Transfer claimed NFT with ChipAuth (pubkey must match token).
    #[allow(clippy::too_many_arguments)]
    fn transfer(
        e: &Env,
        from: Address,
        to: Address,
        token_id: u32,
        message: Bytes,
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

    /// Verify ChipAuth + monotonic nonce for `public_key` (curve from storage).
    fn verify_chip_signature(
        e: &Env,
        signer: Bytes,
        message: Bytes,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    );
}
