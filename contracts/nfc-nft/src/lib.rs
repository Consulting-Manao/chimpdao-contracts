#![no_std]
#![allow(dead_code)]

use soroban_sdk::{contract, contractmeta, Env, Address, String, BytesN, Bytes};

contractmeta!(key = "Description", val = "ChimpDAO NFC-NFT");

mod contract;

#[cfg(test)]
mod test;
mod errors;
mod events;

#[contract]
pub struct NFCtoNFT;

pub trait NFCtoNFTTrait {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String, max_tokens: u32);

    fn upgrade(e: &Env, wasm_hash: BytesN<32>);

    /// Mint NFT using NFC chip signature.
    ///
    /// This function verifies that the provided signature was created by an Infineon
    /// NFC chip by recovering the chip's public key. The public key is converted to
    /// a SEP-50 compliant u32 token_id.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `to` - Account of the token's owner.
    /// * `message` - The message that was signed (without signer and nonce).
    /// * `signature` - 64-byte ECDSA signature from NFC chip.
    /// * `recovery_id` - Recovery ID (0-3) for signature recovery.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    /// * `nonce` - A nonce to prevent replay attacks.
    ///
    /// # Returns
    ///
    /// The u32 token_id (SEP-50 compliant) if signature is valid.
    ///
    /// # Panics
    ///
    /// * If the caller is not the admin.
    /// * If the signature is invalid.
    /// * If the token was already minted.
    /// * If there are no more tokens to be minted.
    ///
    /// # Events
    ///
    /// * topics - `["mint", to: Address]`
    /// * data - `[token_id: u32]`
    fn mint(e: &Env, message: Bytes, signature: BytesN<64>, recovery_id: u32, public_key: BytesN<65>, nonce: u32) -> u32;

    /// Claim NFT using NFC chip signature.
    ///
    /// This function verifies that the provided signature was created by an Infineon
    /// NFC chip by recovering the chip's public key. The public key is converted to
    /// a SEP-50 compliant u32 token_id.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `claimant` - Account of the claimant.
    /// * `message` - The message that was signed (without signer and nonce).
    /// * `signature` - 64-byte ECDSA signature from NFC chip.
    /// * `recovery_id` - Recovery ID (0-3) for signature recovery.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    /// * `nonce` - A nonce to prevent replay attacks.
    ///
    /// # Returns
    ///
    /// The u32 token_id (SEP-50 compliant) if signature is valid.
    ///
    /// # Panics
    ///
    /// * If the claimant is not the signer.
    /// * If the signature is invalid.
    /// * If the token was not yet minted.
    /// * If the token was already claimed.
    ///
    /// # Events
    ///
    /// * topics - `["claim", claimant: Address]`
    /// * data - `[token_id: u32]`
    fn claim(e: &Env, claimant: Address, message: Bytes, signature: BytesN<64>, recovery_id: u32, public_key: BytesN<65>, nonce: u32) -> u32;

    /// Transfers `token_id` token from `from` to `to` using NFC chip signature.
    ///
    /// This function verifies that the provided signature was created by a
    /// NFC chip whose public key corresponds to the token being transferred.
    ///
    /// WARNING: Note that the caller is responsible to confirm that the
    /// recipient is capable of receiving the `Non-Fungible` or else the NFT
    /// may be permanently lost.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `from` - Account of the sender.
    /// * `to` - Account of the recipient.
    /// * `token_id` - Token id as a number.
    /// * `message` - The message that was signed (without signer and nonce).
    /// * `signature` - 64-byte ECDSA signature from NFC chip.
    /// * `recovery_id` - Recovery ID (0-3) for signature recovery.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    /// * `nonce` - A nonce to prevent replay attacks.
    ///
    /// # Panics
    ///
    /// * If the caller is not the owner of the token.
    /// * If the token was not claimed.
    /// * If the signature is invalid.
    /// * If the token was not yet minted.
    /// * If the token was already claimed.
    ///
    /// # Events
    ///
    /// * topics - `["transfer", from: Address, to: Address]`
    /// * data - `[token_id: u32]`
    fn transfer(e: &Env, from: Address, to: Address, token_id: u32, message: Bytes, signature: BytesN<64>, recovery_id: u32, public_key: BytesN<65>, nonce: u32);

    /// Clawback `token_id` token from owner.
    ///
    /// Only the admin can execute this function which sends the token to the
    /// admin address. This is an extreme measure which quarantines
    /// the token. Used in case of terms breach.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `token_id` - Token id as a number.
    ///
    /// # Events
    ///
    /// * topics - `["clawback", from: Address]`
    /// * data - `[token_id: u32]`
    fn clawback(e: &Env, token_id: u32);

    /// Returns the current nonce for the given `public_key`.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    ///
    /// # Returns
    ///
    /// The current nonce for this chip's public_key (defaults to 0 if not set).
    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32;

    /// Returns the number of tokens in `owner`'s account.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `owner` - Account of the token's owner.
    fn balance(e: &Env, owner: Address) -> u32;

    /// Returns the address of the owner of the given `token_id`.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `token_id` - Token id as a number.
    ///
    /// # Notes
    ///
    /// If the token does not exist, this function is expected to panic.
    fn owner_of(e: &Env, token_id: u32) -> Address;

    /// Returns the token collection name.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    fn name(e: &Env) -> String;

    /// Returns the token collection symbol.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    fn symbol(e: &Env) -> String;

    /// Returns the Uniform Resource Identifier (URI) for `token_id` token.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `token_id` - Token id as a number.
    ///
    /// # Notes
    ///
    /// If the token does not exist, this function is expected to panic.
    fn token_uri(e: &Env, token_id: u32) -> String;

    /// Returns the token ID for the given chip public key.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    ///
    /// # Returns
    ///
    /// The token ID associated with this public key, or panics if not found.
    fn token_id(e: &Env, public_key: BytesN<65>) -> u32;

    /// Returns the next token ID to mint.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    ///
    /// # Returns
    ///
    /// The next token ID in the enumeration.
    fn next_token_id(e: &Env) -> u32;

    /// Returns the chip public key for the given token ID.
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `token_id` - Token id as a number.
    ///
    /// # Returns
    ///
    /// The chip's public key associated with this token ID.
    ///
    /// # Panics
    ///
    /// * If the token does not exist.
    fn public_key(e: &Env, token_id: u32) -> BytesN<65>;

    /// Verify the chip signature.
    ///
    /// Verifies that the signature was created by the chip with the given public_key
    /// Also handles nonce verification and updates the stored nonce for the `public_key`
    ///
    /// # Arguments
    ///
    /// * `e` - The environment object.
    /// * `signer` - Address of the signer of the message.
    /// * `message` - The message that was signed (without signer and nonce).
    /// * `signature` - 64-byte ECDSA signature from NFC chip.
    /// * `recovery_id` - Recovery ID (0-3) for signature recovery.
    /// * `public_key` - The chip's public key (uncompressed SEC1 format, 65 bytes).
    /// * `nonce` - A nonce to prevent replay attacks.
    fn verify_chip_signature(
        e: &Env,
        signer: Bytes,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    );
}