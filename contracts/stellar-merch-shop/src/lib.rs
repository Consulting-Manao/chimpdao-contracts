#![no_std]
#![allow(dead_code)]


use soroban_sdk::{contract, contractmeta, Env, Address, String, BytesN, Bytes};

contractmeta!(key = "Description", val = "Stellar Merch Shop");

mod contract;

#[cfg(test)]
mod test;
mod errors;
mod events;

#[contract]
pub struct StellarMerchShop;

pub trait NFCtoNFTContract {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String);

    /// Mint NFT using NFC chip signature.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `to` - Account of the token's owner.
    /// * `message` - The message that was signed (will be hashed in contract).
    /// * `signature` - 64-byte ECDSA signature from NFC chip (r + s).
    /// * `recovery_id` - Recovery ID (0-3) for public key recovery.
    ///
    /// # Returns
    ///
    /// The recovered 65-byte public key, which becomes the token ID.
    fn mint(e: &Env, to: Address, message: Bytes, signature: BytesN<64>, recovery_id: u32) -> BytesN<65>;

    /// Returns the number of tokens in `owner`'s account.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `owner` - Account of the token's owner.
    fn balance(e: &Env, owner: Address) -> u32;

    /// Returns the address of the owner of the given `token_id`.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `token_id` - Token id as a number.
    ///
    /// # Notes
    ///
    /// If the token does not exist, this function is expected to panic.
    fn owner_of(e: &Env, token_id: u32) -> Address;

    /// Transfers `token_id` token from `from` to `to`.
    ///
    /// WARNING: Note that the caller is responsible to confirm that the
    /// recipient is capable of receiving the `Non-Fungible` or else the NFT
    /// may be permanently lost.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `from` - Account of the sender.
    /// * `to` - Account of the recipient.
    /// * `token_id` - Token id as a number.
    ///
    /// # Events
    ///
    /// * topics - `["transfer", from: Address, to: Address]`
    /// * data - `[token_id: u32]`
    fn transfer(e: &Env, from: Address, to: Address, token_id: u32);

    /// Transfers `token_id` token from `from` to `to` by using `spender`s
    /// approval.
    ///
    /// Unlike `transfer()`, which is used when the token owner initiates the transfer,
    /// `transfer_from()` allows an approved third party (`spender`) to transfer the token
    /// on behalf of the owner. This function includes an on-chain check to verify that
    /// `spender` has the necessary approval.
    ///
    /// WARNING: Note that the caller is responsible to confirm that the
    /// recipient is capable of receiving the `Non-Fungible` or else the NFT
    /// may be permanently lost.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `spender` - The address authorizing the transfer.
    /// * `from` - Account of the sender.
    /// * `to` - Account of the recipient.
    /// * `token_id` - Token id as a number.
    ///
    /// # Events
    ///
    /// * topics - `["transfer", from: Address, to: Address]`
    /// * data - `[token_id: u32]`
    fn transfer_from(e: &Env, spender: Address, from: Address, to: Address, token_id: u32);

    /// Gives permission to `approved` to transfer `token_id` token to another
    /// account. The approval is cleared when the token is transferred.
    ///
    /// Only a single account can be approved at a time for a `token_id`.
    /// To remove an approval, the approver can approve their own address,
    /// effectively removing the previous approved address.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to Soroban environment.
    /// * `approver` - The address of the approver (should be `owner` or `operator`).
    /// * `approved` - The address receiving the approval.
    /// * `token_id` - Token id as a number.
    /// * `live_until_ledger` - The ledger number at which the allowance
    ///   expires.
    ///
    /// # Events
    ///
    /// * topics - `["approve", from: Address, to: Address]`
    /// * data - `[token_id: u32, live_until_ledger: u32]`
    fn approve(e: &Env, approver: Address, approved: Address, token_id: u32, live_until_ledger: u32);

    /// Approve or remove `operator` as an operator for the owner.
    ///
    /// Operators can call `transfer_from()` for any token held by `owner`,
    /// and call `approve()` on behalf of `owner`.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to Soroban environment.
    /// * `owner` - The address holding the tokens.
    /// * `operator` - Account to add to the set of authorized operators.
    /// * `live_until_ledger` - The ledger number at which the allowance
    ///   expires. If `live_until_ledger` is `0`, the approval is revoked.
    ///
    /// # Events
    ///
    /// * topics - `["approve_for_all", from: Address]`
    /// * data - `[operator: Address, live_until_ledger: u32]`
    fn approve_for_all(
        e: &Env,
        owner: Address,
        operator: Address,
        live_until_ledger: u32,
    );

    /// Returns the account approved for `token_id` token.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `token_id` - Token id as a number.
    ///
    /// # Notes
    ///
    /// If the token does not exist, this function is expected to panic.
    fn get_approved(e: &Env, token_id: u32) -> Option<Address>;

    /// Returns whether the `operator` is allowed to manage all the assets of
    /// `owner`.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `owner` - Account of the token's owner.
    /// * `operator` - Account to be checked.
    fn is_approved_for_all(e: &Env, owner: Address, operator: Address) -> bool;

    /// Returns the token collection name.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    fn name(e: &Env) -> String;

    /// Returns the token collection symbol.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    fn symbol(e: &Env) -> String;

    /// Returns the Uniform Resource Identifier (URI) for `token_id` token.
    ///
    /// # Arguments
    ///
    /// * `e` - Access to the Soroban environment.
    /// * `token_id` - Token id as a number.
    ///
    /// # Notes
    ///
    /// If the token does not exist, this function is expected to panic.
    fn token_uri(e: &Env, token_id: u32) -> String;
}