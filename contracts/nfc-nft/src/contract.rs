//! NFC - NFT binding

use crate::{NFCtoNFT, NFCtoNFTArgs, NFCtoNFTClient, NFCtoNFTTrait, errors, events};
use chimpdao_chip_auth::{ChipAuth, Curve};
use soroban_sdk::{
    Address, Bytes, BytesN, Env, IntoVal, String, Symbol, Val, Vec, contractclient, contractimpl,
    contracttype, panic_with_error,
};
/// The Chimp account's signer set. A card's 65-byte key is its whole identity here —
/// there is no rule id to name and no verifier address to agree on.
#[contractclient(name = "AccountClient")]
#[allow(dead_code)]
trait AccountCards {
    fn has_card(e: Env, key: BytesN<65>) -> bool;
    fn cards(e: Env) -> Vec<CardSigner>;
    fn add_card(e: Env, card: CardSigner);
    fn remove_card(e: Env, key: BytesN<65>);
    fn abandon(e: Env);
}

/// Mirrors `chimpdao-account`'s signer record. Declared rather than imported so this
/// contract does not depend on the account crate.
#[contracttype]
#[derive(Clone)]
pub struct CardSigner {
    pub key: BytesN<65>,
    pub curve: Curve,
}

/// The purse follows the card.
#[contractclient(name = "PocketClient")]
#[allow(dead_code)]
trait PocketOwner {
    fn set_owner(e: Env, new_owner: Address);
}

/// Pocket lookup by chip key.
#[contractclient(name = "FactoryClient")]
#[allow(dead_code)]
trait PocketFactory {
    fn get_account(e: Env, public_key: BytesN<65>) -> Option<Address>;
}

/// The collection registry's owner index, updated whenever a token changes hands.
#[contractclient(name = "CollectionClient")]
#[allow(dead_code)]
trait CollectionIndex {
    fn assign_collectible(e: Env, collection: Address, to: Address, token_id: u32);
}

/// Domain separator for every chip attestation this contract accepts. Bump the suffix if
/// the digest construction changes.
const DOMAIN: &[u8] = b"chimpdao.nfc-nft.v2";

#[contracttype]
pub enum DataKey {
    Admin,
    CollectionContract,
    NextTokenId,
    MaxTokens,
    Name,
    Symbol,
    Uri,
    /// ERC-7496 trait schema location.
    TraitUri,
    /// Pocket factory — resolves a card's purse for the atomic handover.
    Factory,
}

#[contracttype]
pub enum NFTStorageKey {
    ChipNonceByPublicKey(BytesN<65>),
    ChipCurveByPublicKey(BytesN<65>),
    Owner(u32),
    PublicKey(u32),
    TokenIdByPublicKey(BytesN<65>),
    Balance(Address),
    /// ERC-7496 stored trait: the card's tier, which drives its art.
    Tier(u32),
}

#[contractimpl]
impl NFCtoNFTTrait for NFCtoNFT {
    #[allow(clippy::too_many_arguments)]
    fn __constructor(
        e: &Env,
        admin: Address,
        collection_contract: Address,
        name: String,
        symbol: String,
        uri: String,
        max_tokens: u32,
    ) {
        e.storage().instance().set(&DataKey::Admin, &admin);

        e.storage()
            .instance()
            .set(&DataKey::CollectionContract, &collection_contract);

        e.storage().instance().set(&DataKey::Name, &name);
        e.storage().instance().set(&DataKey::Symbol, &symbol);
        e.storage().instance().set(&DataKey::Uri, &uri);

        e.storage().instance().set(&DataKey::MaxTokens, &max_tokens);
        e.storage().instance().set(&DataKey::NextTokenId, &0u32);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        e.deployer().update_current_contract_wasm(wasm_hash.clone());
    }

    fn set_factory(e: &Env, factory: Address) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.storage().instance().set(&DataKey::Factory, &factory);
    }

    /// Stateless chip-signature oracle over the registry's stored curve. Replay is the
    /// caller's digest contract: callers must put their own nonce/expiry inside
    /// `digest` (the Pocket passes the host authorization payload; attestation
    /// integrators bring a domain + nonce). Unknown cards verify false.
    fn verify_for_card(e: &Env, public_key: BytesN<65>, digest: Bytes, auth: ChipAuth) -> bool {
        let Some(curve): Option<Curve> = e
            .storage()
            .persistent()
            .get(&NFTStorageKey::ChipCurveByPublicKey(public_key.clone()))
        else {
            return false;
        };
        let variant_matches = matches!(
            (&curve, &auth),
            (Curve::Secp256k1, ChipAuth::Secp256k1(_)) | (Curve::Secp256r1, ChipAuth::Secp256r1(_))
        );
        if !variant_matches {
            return false;
        }
        chimpdao_chip_auth::verify_digest_bytes(e, &digest, &public_key, auth)
    }

    fn mint(e: &Env, auth: ChipAuth, public_key: BytesN<65>, curve: Curve, nonce: u32) -> u32 {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        // Curve is not in storage yet — this call is what records it.
        Self::verify_chip(
            e,
            &Symbol::new(e, "mint"),
            Vec::from_array(
                e,
                [public_key.clone().into_val(e), curve.clone().into_val(e)],
            ),
            auth,
            public_key.clone(),
            curve.clone(),
            nonce,
        );

        let public_key_lookup = NFTStorageKey::TokenIdByPublicKey(public_key.clone());
        if e.storage().persistent().has(&public_key_lookup) {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenAlreadyMinted);
        }

        let token_id: u32 = Self::next_token_id(e);
        let max_tokens: u32 = e.storage().instance().get(&DataKey::MaxTokens).unwrap();

        if token_id >= max_tokens {
            panic_with_error!(&e, &errors::NonFungibleTokenError::TokenIDsAreDepleted);
        }

        e.storage()
            .instance()
            .set(&DataKey::NextTokenId, &(token_id + 1));
        e.storage().persistent().set(&public_key_lookup, &token_id);
        e.storage()
            .persistent()
            .set(&NFTStorageKey::PublicKey(token_id), &public_key);
        e.storage().persistent().set(
            &NFTStorageKey::ChipCurveByPublicKey(public_key.clone()),
            &curve,
        );

        let contract_address = e.current_contract_address();
        events::Mint {
            to: contract_address,
            token_id,
        }
        .publish(e);

        token_id
    }

    fn claim(
        e: &Env,
        claimant: Address,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    ) -> u32 {
        claimant.require_auth();
        Self::require_member(e, &claimant, &public_key);

        Self::verify_chip_stored_curve(
            e,
            &Symbol::new(e, "claim"),
            Vec::from_array(e, [claimant.clone().into_val(e)]),
            auth,
            public_key.clone(),
            nonce,
        );

        let token_id = Self::token_id(e, public_key.clone());

        if e.storage()
            .persistent()
            .has(&NFTStorageKey::Owner(token_id))
        {
            panic_with_error!(e, &errors::NonFungibleTokenError::TokenAlreadyClaimed);
        }

        e.storage()
            .persistent()
            .set(&NFTStorageKey::Owner(token_id), &claimant);

        let claimant_balance = Self::balance(e, claimant.clone());
        e.storage().persistent().set(
            &NFTStorageKey::Balance(claimant.clone()),
            &(claimant_balance + 1),
        );

        assign_collectible(e, &claimant, &token_id);

        events::Claim { claimant, token_id }.publish(e);

        token_id
    }

    #[allow(clippy::too_many_arguments)]
    fn transfer(
        e: &Env,
        from: Address,
        to: Address,
        token_id: u32,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    ) {
        from.require_auth();

        Self::verify_chip_stored_curve(
            e,
            &Symbol::new(e, "transfer"),
            Vec::from_array(
                e,
                [
                    from.clone().into_val(e),
                    to.clone().into_val(e),
                    token_id.into_val(e),
                ],
            ),
            auth,
            public_key.clone(),
            nonce,
        );

        // Verify the chip public_key corresponds to that specific token_id
        let token_id_public_key: BytesN<65> = Self::public_key(e, token_id);

        if token_id_public_key != public_key {
            panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
        }

        let owner = Self::owner_of(e, token_id);
        if owner != from || from == to {
            panic_with_error!(e, &errors::NonFungibleTokenError::IncorrectOwner);
        }

        e.storage()
            .persistent()
            .set(&NFTStorageKey::Owner(token_id), &to);

        let from_balance = Self::balance(e, from.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(from.clone()), &(from_balance - 1));
        let to_balance = Self::balance(e, to.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(to.clone()), &(to_balance + 1));

        assign_collectible(e, &to, &token_id);

        // --- the card moves as one object: membership + purse follow the token ---
        let card = CardSigner {
            key: public_key.clone(),
            curve: Self::curve(e, public_key.clone()),
        };

        // Join the destination first (skipped when it already lists the card, e.g. a
        // fresh account founded by it). Requires `to`'s own authorization.
        let to_client = AccountClient::new(e, &to);
        if !to_client.has_card(&public_key) {
            to_client.add_card(&card);
        }

        // Purse follows — owner-gated, covered by `from`'s auth tree. Its DeFi positions
        // travel with it, which is the point: gifting a loaded card needs no unwind.
        if let Some(pocket) = e
            .storage()
            .instance()
            .get::<_, Address>(&DataKey::Factory)
            .and_then(|factory| FactoryClient::new(e, &factory).get_account(&public_key))
        {
            PocketClient::new(e, &pocket).set_owner(&to);
        }

        // Leave the source last. `remove_card` refuses to strip an account's only signer,
        // so a sole card is handed over with `abandon` — the holder is giving up that
        // account deliberately, and its balances moved with the purse.
        let from_client = AccountClient::new(e, &from);
        if !from_client.has_card(&public_key) {
            panic_with_error!(e, &errors::NonFungibleTokenError::NotCardHolder);
        }
        if from_client.cards().len() <= 1 {
            from_client.abandon();
        } else {
            from_client.remove_card(&public_key);
        }
        // Identity is the key itself, so leaving is exact — there is no second rule the
        // card could still be listed in.

        events::Transfer { from, to, token_id }.publish(e);
    }

    fn clawback(e: &Env, token_id: u32) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        let from = Self::owner_of(e, token_id);
        let to = admin.clone();

        e.storage()
            .persistent()
            .set(&NFTStorageKey::Owner(token_id), &to);

        let from_balance = Self::balance(e, from.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(from.clone()), &(from_balance - 1));
        let to_balance = Self::balance(e, to.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(to.clone()), &(to_balance + 1));

        assign_collectible(e, &to, &token_id);
    }

    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32 {
        let nonce_key = NFTStorageKey::ChipNonceByPublicKey(public_key);
        e.storage().persistent().get(&nonce_key).unwrap_or(0u32) // Default to 0 if not set (first use)
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
        e.storage()
            .persistent()
            .get(&NFTStorageKey::Owner(token_id))
            .unwrap_or_else(|| panic_with_error!(e, errors::NonFungibleTokenError::TokenNotClaimed))
    }

    fn name(e: &Env) -> String {
        e.storage().instance().get(&DataKey::Name).unwrap()
    }

    fn symbol(e: &Env) -> String {
        e.storage().instance().get(&DataKey::Symbol).unwrap()
    }

    fn token_uri(e: &Env, token_id: u32) -> String {
        // Verify token exists (this will panic if it doesn't)
        Self::public_key(e, token_id);

        let base_uri: String = e.storage().instance().get(&DataKey::Uri).unwrap();

        // Construct Uri: {base_uri}/{token_id}
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
            .unwrap_or_else(|| {
                panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken)
            })
    }

    fn next_token_id(e: &Env) -> u32 {
        e.storage().instance().get(&DataKey::NextTokenId).unwrap()
    }

    fn public_key(e: &Env, token_id: u32) -> BytesN<65> {
        e.storage()
            .persistent()
            .get(&NFTStorageKey::PublicKey(token_id))
            .unwrap_or_else(|| {
                panic_with_error!(e, errors::NonFungibleTokenError::NonExistentToken)
            })
    }

    fn curve(e: &Env, public_key: BytesN<65>) -> Curve {
        e.storage()
            .persistent()
            .get(&NFTStorageKey::ChipCurveByPublicKey(public_key))
            .unwrap_or_else(|| panic_with_error!(&e, &errors::NonFungibleTokenError::MissingCurve))
    }
}

impl NFCtoNFT {
    /// Soulbound: the destination must be an account that lists this card. Identity is
    /// the key itself, so the check is exact — there is no rule or registry entry that
    /// could linger after the card left. Any non-account destination (a G address, a
    /// foreign contract) fails the call and is rejected the same way.
    fn require_member(e: &Env, account: &Address, public_key: &BytesN<65>) {
        let listed = AccountClient::new(e, account)
            .try_has_card(public_key)
            .unwrap_or(Ok(false))
            .unwrap_or(false);
        if !listed {
            panic_with_error!(e, errors::NonFungibleTokenError::NotCardHolder);
        }
    }

    /// Verify a chip attestation using the curve recorded at mint.
    fn verify_chip_stored_curve(
        e: &Env,
        fn_name: &Symbol,
        args: Vec<Val>,
        auth: ChipAuth,
        public_key: BytesN<65>,
        nonce: u32,
    ) {
        let curve = Self::curve(e, public_key.clone());
        Self::verify_chip(e, fn_name, args, auth, public_key, curve, nonce);
    }

    /// The chip attests to *this* call: contract, function, arguments and nonce are all
    /// in the digest, so a signature cannot be moved to another function or arguments.
    fn verify_chip(
        e: &Env,
        fn_name: &Symbol,
        args: Vec<Val>,
        auth: ChipAuth,
        public_key: BytesN<65>,
        curve: Curve,
        nonce: u32,
    ) {
        let nonce_key = NFTStorageKey::ChipNonceByPublicKey(public_key.clone());
        let stored_nonce: u32 = e.storage().persistent().get(&nonce_key).unwrap_or(0u32);

        if nonce <= stored_nonce {
            panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
        }

        let digest = chimpdao_chip_auth::call_digest(
            e,
            DOMAIN,
            &e.current_contract_address(),
            fn_name,
            &args,
            nonce,
        );
        if !chimpdao_chip_auth::verify_chip_auth(e, &digest, &public_key, &curve, auth) {
            panic_with_error!(&e, &errors::NonFungibleTokenError::InvalidSignature);
        }

        e.storage().persistent().set(&nonce_key, &nonce);
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

// update collection
fn assign_collectible(e: &Env, to: &Address, token_id: &u32) {
    let collection_contract_address = e
        .storage()
        .instance()
        .get(&DataKey::CollectionContract)
        .unwrap();
    let client = CollectionClient::new(e, &collection_contract_address);
    client.assign_collectible(&e.current_contract_address(), to, token_id);
}
