//! NFC - NFT binding

use soroban_sdk::{contractimpl, contracttype, panic_with_error, Address, Bytes, BytesN, Env, String};
use soroban_sdk::xdr::ToXdr;
use crate::{errors, events, NFCtoNFT, NFCtoNFTArgs, NFCtoNFTClient, NFCtoNFTTrait};

#[contracttype]
pub enum DataKey {
    Admin,
    NextTokenId,
    MaxTokens,
}

#[contracttype]
pub enum NFTStorageKey {
    ChipNonceByPublicKey(BytesN<65>),
    Owner(u32),
    PublicKey(u32),
    TokenIdByPublicKey(BytesN<65>),
    Balance(Address),
    Name,
    Symbol,
    URI,
}

#[contractimpl]
impl NFCtoNFTTrait for NFCtoNFT {

    fn __constructor(e: &Env, admin: Address, name: String, symbol: String, uri: String, max_tokens: u32) {
        e.storage().instance().set(&DataKey::Admin, &admin);

        e.storage().instance().set(&NFTStorageKey::Name, &name);
        e.storage().instance().set(&NFTStorageKey::Symbol, &symbol);
        e.storage().instance().set(&NFTStorageKey::URI, &uri);

        e.storage().instance().set(&DataKey::MaxTokens, &max_tokens);
        e.storage().instance().set(&DataKey::NextTokenId, &0u32);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        e.deployer().update_current_contract_wasm(wasm_hash.clone());

        events::Upgrade { admin, wasm_hash: wasm_hash.into() }.publish(e);
    }

    fn mint(
        e: &Env,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u32 {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key.clone());
        if e.storage().persistent().has(&public_key_lookup) {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        let token_id: u32 = e
            .storage()
            .instance()
            .get(&DataKey::NextTokenId)
            .unwrap();
        let max_tokens: u32 = e
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

    fn claim(
        e: &Env,
        claimant: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u32 {
        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        // Look up token_id from public_key
        let token_id = Self::token_id(e, public_key.clone());

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
        token_id: u32,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) {
        from.require_auth();

        verify_chip_signature(e, message, signature, recovery_id, public_key.clone(), nonce);

        // Verify the chip public_key corresponds to that specific token_id
        let token_id_public_key: BytesN<65> = Self::public_key(e, token_id);

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

    fn balance(e: &Env, owner: Address) -> u32 {
        e.storage()
            .persistent()
            .get(&NFTStorageKey::Balance(owner))
            .unwrap_or(0u32)
    }

    fn owner_of(e: &Env, token_id: u32) -> Address {
        // Verify the token exists (this will panic if it doesn't)
        Self::public_key(e, token_id);

        // Token exists, now check if it has an owner
        e.storage().persistent()
        .get(&NFTStorageKey::Owner(token_id))
        .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::TokenNotClaimed))
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

    fn token_uri(e: &Env, token_id: u32) -> String {
        // Verify token exists (this will panic if it doesn't)
        Self::public_key(e, token_id);

        let base_uri: String = e
            .storage()
            .instance()
            .get(&NFTStorageKey::URI)
            .unwrap();

        // Construct URI: {base_uri}/{token_id}
        let mut uri_bytes = Bytes::new(e);
        uri_bytes.append(&Bytes::from(base_uri));
        uri_bytes.append(&Bytes::from_slice(e, b"/"));
        uri_bytes.append(&u32_to_decimal_bytes(e, token_id));

        String::from(uri_bytes)
    }

    fn token_id(e: &Env, public_key: BytesN<65>) -> u32 {
        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key);
        e.storage()
            .persistent()
            .get::<NFTStorageKey, u32>(&public_key_lookup)
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }

    fn public_key(e: &Env, token_id: u32) -> BytesN<65> {
        e.storage()
            .persistent()
            .get(&NFTStorageKey::PublicKey(token_id))
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken))
    }
}

/// Convert an u32 to its decimal string representation as Bytes
/// Implementation inspired by OpenZeppelin's token_id_to_string
pub(crate) fn u32_to_decimal_bytes(e: &Env, mut value: u32) -> Bytes {
    if value == 0 {
        return Bytes::from_slice(e, b"0");
    }

    // Count digits (equivalent to log10(value) + 1 in no_std)
    let mut temp = value;
    let mut length = 0;
    while temp > 0 {
        length += 1;
        temp /= 10;
    }

    // Allocate buffer with max size (20 for u32)
    let mut buffer = [0u8; 20];

    // Fill from right to left (most significant digit first)
    let mut i = length;
    while value > 0 {
        i -= 1;
        buffer[i] = b'0' + (value % 10) as u8;
        value /= 10;
    }

    Bytes::from_slice(e, &buffer[..length])
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
