//! NFT - NFT binding

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, NFCtoNFTContract, StellarMerchShop, StellarMerchShopArgs, StellarMerchShopClient};

#[contracttype]
pub enum DataKey {
    Admin,
    Nonce,
}

#[contracttype]
pub enum NFTStorageKey {
    ChipNonce(BytesN<65>),
    Owner(BytesN<65>),
    Balance(Address),
    Approval(u32),
    ApprovalForAll(Address /* owner */, Address /* operator */),
    Name,
    Symbol,
    URI,
}


#[contractimpl]
impl NFCtoNFTContract for StellarMerchShop {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String) {
        e.storage().instance().set(&DataKey::Admin, &admin);

        e.storage().instance().set(&NFTStorageKey::Name, &name);
        e.storage().instance().set(&NFTStorageKey::Symbol, &symbol);
        e.storage().instance().set(&NFTStorageKey::URI, &uri);
    }

    fn mint(
        e: &Env,
        to: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        nonce: u32,
    ) -> BytesN<65> {
        let mut builder: Bytes = Bytes::new(&e);
        builder.append(&message.clone());
        builder.append(&nonce.clone().to_xdr(&e));

        // Hash the message to get Hash<32> for signature recovery
        // This ensures Hash is constructed via a secure cryptographic function
        let message_hash = e.crypto().sha256(&builder);

        // Recover the NFC chip's public key from the signature
        // This proves the signature was created by the chip holding the private key
        let token_id = e.crypto().secp256k1_recover(&message_hash, &signature, recovery_id);

        let owner_key = NFTStorageKey::Owner(token_id.clone());

        if e
            .storage()
            .persistent()
            .get::<NFTStorageKey, BytesN<65>>(&owner_key)
            .is_some()
        {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        e.storage().persistent().set(&owner_key, &to);

        // TODO
        // - Update balance: increment to's token count
        // - update counter collection itself

        e.storage().persistent().set(&NFTStorageKey::ChipNonce(token_id.clone()), &nonce);

        events::Mint { to, token_id: token_id.clone() }.publish(&e);

        token_id
    }

    fn balance(e: &Env, owner: Address) -> u32 {
        todo!()
    }

    fn owner_of(e: &Env, token_id: BytesN<65>) -> Address {
        e.storage().persistent()
        .get(&NFTStorageKey::Owner(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn transfer(e: &Env, from: Address, to: Address, token_id: BytesN<65>) {
        todo!()
    }

    fn transfer_from(e: &Env, spender: Address, from: Address, to: Address, token_id: BytesN<65>) {
        todo!()
    }

    fn approve(e: &Env, approver: Address, approved: Address, token_id: BytesN<65>, live_until_ledger: u32) {
        todo!()
    }

    fn approve_for_all(e: &Env, owner: Address, operator: Address, live_until_ledger: u32) {
        todo!()
    }

    fn get_approved(e: &Env, token_id: BytesN<65>) -> Option<Address> {
        todo!()
    }

    fn is_approved_for_all(e: &Env, owner: Address, operator: Address) -> bool {
        todo!()
    }

    fn get_nonce(e: &Env, token_id: BytesN<65>) -> u32 {
        e.storage().persistent()
        .get(&NFTStorageKey::ChipNonce(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn name(e: &Env) -> String {
            e.storage()
            .instance()
            .get(&NFTStorageKey::Name)
            .unwrap()
    }

    fn symbol(e: &Env) -> String {
            e.storage()
            .instance()
            .get(&NFTStorageKey::Symbol)
            .unwrap()
    }

    fn token_uri(e: &Env, token_id: BytesN<65>) -> String {
        todo!()
    }

}
