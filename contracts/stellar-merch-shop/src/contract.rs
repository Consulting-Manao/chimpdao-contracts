//! NFT - NFT binding

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, NFCtoNFTContract, StellarMerchShop, StellarMerchShopArgs, StellarMerchShopClient};

#[contracttype]
pub enum DataKey {
    Admin,
    NextTokenId,
    MaxTokens,
}

#[contracttype]
pub enum NFTStorageKey {
    ChipNonceByPublicKey(BytesN<65>),
    Owner(u64),
    PublicKey(u64),
    TokenIdByPublicKey(BytesN<65>),
    Balance(Address),
    Name,
    Symbol,
    URI,
}

#[contractimpl]
impl NFCtoNFTContract for StellarMerchShop {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String, max_tokens: u64) {
        e.storage().instance().set(&DataKey::Admin, &admin);

        e.storage().instance().set(&NFTStorageKey::Name, &name);
        e.storage().instance().set(&NFTStorageKey::Symbol, &symbol);
        e.storage().instance().set(&NFTStorageKey::URI, &uri);

        e.storage().instance().set(&DataKey::MaxTokens, &max_tokens);
        e.storage().instance().set(&DataKey::NextTokenId, &0u64);
    }

    fn mint(
        e: &Env,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u64 {
        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key.clone());
        if e
            .storage()
            .persistent()
            .get::<NFTStorageKey, u64>(&public_key_lookup)
            .is_some()
        {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        let token_id: u64 = e
            .storage()
            .instance()
            .get(&DataKey::NextTokenId)
            .unwrap();
        let max_tokens: u64 = e
            .storage()
            .instance()
            .get(&DataKey::MaxTokens)
            .unwrap();

        if token_id >= max_tokens {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenIDsAreDepleted);
        }

        e.storage().instance().set(&DataKey::NextTokenId, &(token_id + 1));
        e.storage().persistent().set(&public_key_lookup, &token_id);
        e.storage().persistent().set(&NFTStorageKey::PublicKey(token_id), &public_key);

        events::Mint { token_id }.publish(&e);

        token_id
    }

    fn balance(e: &Env, owner: Address) -> u32 {
        e.storage()
            .persistent()
            .get(&NFTStorageKey::Balance(owner))
            .unwrap_or(0u32)
    }

    fn owner_of(e: &Env, token_id: u64) -> Address {
        e.storage().persistent()
        .get(&NFTStorageKey::Owner(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn claim(
        e: &Env,
        claimant: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u64 {
        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        // Look up token_id from public_key
        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key.clone());
        let token_id: u64 = e
            .storage()
            .persistent()
            .get::<NFTStorageKey, u64>(&public_key_lookup)
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken));

        // Verify token is not already claimed
        if e.storage().persistent().has(&NFTStorageKey::Owner(token_id)) {
            panic_with_error!(e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        e.storage().persistent().set(&NFTStorageKey::Owner(token_id), &claimant);

        let claimant_balance = Self::balance(e, claimant.clone());
        e.storage().persistent().set(&NFTStorageKey::Balance(claimant.clone()), &(claimant_balance + 1));

        events::Claim { claimant, token_id }.publish(&e);

        token_id
    }

    fn transfer(
        e: &Env,
        from: Address,
        to: Address,
        token_id: u64,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) {
        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        // Verify the chip public_key corresponds to that specific token_id
        let token_id_public_key: BytesN<65> = e.storage()
            .persistent()
            .get(&NFTStorageKey::PublicKey(token_id))
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken));

        if token_id_public_key != public_key {
            panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
        }

        let owner = Self::owner_of(e, token_id);
        if owner != from || from == to {
            panic_with_error!(e, &errors::NonFungibleTokenError::IncorrectOwner);
        }

        e.storage().persistent().set(&NFTStorageKey::Owner(token_id), &to);

        let from_balance = Self::balance(e, from.clone());
        e.storage().persistent().set(&NFTStorageKey::Balance(from.clone()), &(from_balance - 1));
        let to_balance = Self::balance(e, to.clone());
        e.storage().persistent().set(&NFTStorageKey::Balance(to.clone()), &(to_balance + 1));

        events::Transfer { from, to, token_id }.publish(e);
    }

    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32 {
        let nonce_key = NFTStorageKey::ChipNonceByPublicKey(public_key);
        e.storage()
            .persistent()
            .get(&nonce_key)
            .unwrap_or(0u32)  // Default to 0 if not set (first use)
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

    fn token_uri(e: &Env, token_id: u64) -> String {
        // Verify token exists by checking if public_key is stored (works for both claimed and unclaimed tokens)
        let _public_key: BytesN<65> = e.storage()
            .persistent()
            .get(&NFTStorageKey::PublicKey(token_id))
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken));

        let base_uri: String = e
            .storage()
            .instance()
            .get(&NFTStorageKey::URI)
            .unwrap();

        // Construct URI: {base_uri}/{token_id}
        let mut uri_bytes = Bytes::new(e);
        uri_bytes.append(&Bytes::from(base_uri));
        uri_bytes.append(&Bytes::from_slice(e, b"/"));
        uri_bytes.append(&u64_to_decimal_bytes(e, token_id));

        String::from(uri_bytes)
    }

}

/// Convert a u64 to its decimal string representation as Bytes
fn u64_to_decimal_bytes(e: &Env, mut num: u64) -> Bytes {
    if num == 0 {
        return Bytes::from_slice(e, b"0");
    }

    // Maximum digits for u64 is 20 (2^64 - 1 = 18446744073709551615)
    let mut digits = [0u8; 20];
    let mut len = 0;

    while num > 0 {
        digits[len] = b'0' + (num % 10) as u8;
        len += 1;
        num /= 10;
    }

    // Reverse the digits since we collected them in reverse order
    for i in 0..len / 2 {
        let temp = digits[i];
        digits[i] = digits[len - 1 - i];
        digits[len - 1 - i] = temp;
    }

    Bytes::from_slice(e, &digits[..len])
}

/// Common function to verify chip signature
/// Verifies that the signature was created by the chip with the given public_key
/// Also handles nonce verification and updates the stored nonce for the public_key
fn verify_chip_signature(
    e: &Env,
    message: Bytes,
    signature: BytesN<64>,
    recovery_id: u32,
    public_key: BytesN<65>,
    nonce: u32,
) {
    let nonce_key = NFTStorageKey::ChipNonceByPublicKey(public_key.clone());
    let stored_nonce: u32 = e.storage()
        .persistent()
        .get(&nonce_key)
        .unwrap_or(0u32);

    // Verify nonce is monotonic increasing
    if nonce <= stored_nonce {
        panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
    }

    // Build message hash with nonce
    let mut builder: Bytes = Bytes::new(&e);
    builder.append(&message.clone());
    builder.append(&nonce.clone().to_xdr(&e));
    let message_hash = e.crypto().sha256(&builder);

    // Verify signature recovers to the public_key
    let recovered = e.crypto().secp256k1_recover(&message_hash, &signature, recovery_id);
    if recovered != public_key {
        panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
    }
    
    // Update stored nonce for this public_key
    e.storage().persistent().set(&nonce_key, &nonce);
}
