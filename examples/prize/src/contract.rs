//! Prize contract implementation.
//!
//! Lock a token per chip public key; redeeming requires a chip attestation for *this*
//! call plus ownership of the matching NFT.

use crate::{ChipAuth, Prize, PrizeArgs, PrizeClient, PrizeTrait, errors, events, nfc_contract};
use soroban_sdk::{
    Address, BytesN, Env, IntoVal, Symbol, Val, Vec, contractimpl, contracttype, panic_with_error,
    token::TokenClient,
};

/// Distinct from `nfc-nft`'s, so attestations cannot cross between them.
const DOMAIN: &[u8] = b"chimpdao.prize.v1";

/// `contractimport!` generates its own `Curve` from the imported spec: XDR-identical to
/// `chimpdao_chip_auth::Curve` but a distinct Rust type. Every integrator hits this.
fn shared_curve(curve: nfc_contract::Curve) -> chimpdao_chip_auth::Curve {
    match curve {
        nfc_contract::Curve::Secp256k1 => chimpdao_chip_auth::Curve::Secp256k1,
        nfc_contract::Curve::Secp256r1 => chimpdao_chip_auth::Curve::Secp256r1,
    }
}

#[contracttype]
pub enum DataKey {
    Admin,
    Token,
    NfcContract,
}

#[contracttype]
pub enum StorageKey {
    Vault(BytesN<65>),
    Nonce(BytesN<65>),
}

#[contractimpl]
impl PrizeTrait for Prize {
    fn __constructor(e: &Env, admin: Address, token: Address, nfc_contract: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
        e.storage().instance().set(&DataKey::Token, &token);
        e.storage()
            .instance()
            .set(&DataKey::NfcContract, &nfc_contract);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn nfc_contract(e: &Env) -> Address {
        e.storage().instance().get(&DataKey::NfcContract).unwrap()
    }

    fn deposit(e: &Env, from: Address, amount: i128, token_id: u32) {
        from.require_auth();

        if amount <= 0 {
            panic_with_error!(e, &errors::PrizeError::InvalidAmount);
        }

        let token: Address = e.storage().instance().get(&DataKey::Token).unwrap();
        let contract = e.current_contract_address();
        TokenClient::new(e, &token).transfer(&from, &contract, &amount);

        let nfc = Self::nfc_contract(e);
        let chip_public_key = nfc_contract::Client::new(e, &nfc).public_key(&token_id);
        let key = StorageKey::Vault(chip_public_key);
        let current: i128 = e.storage().persistent().get(&key).unwrap_or(0i128);
        e.storage().persistent().set(&key, &(current + amount));

        events::Deposit {
            token_id,
            amount,
            from,
        }
        .publish(e);
    }

    fn redeem(e: &Env, redeemer: Address, auth: ChipAuth, public_key: BytesN<65>, nonce: u32) {
        redeemer.require_auth();

        let nfc = Self::nfc_contract(e);
        let nfc_client = nfc_contract::Client::new(e, &nfc);

        // Chip attestation, bound to this call.
        let stored_nonce: u32 = e
            .storage()
            .persistent()
            .get(&StorageKey::Nonce(public_key.clone()))
            .unwrap_or(0u32);
        if nonce <= stored_nonce {
            panic_with_error!(e, &errors::PrizeError::InvalidSignature);
        }

        let args: Vec<Val> = Vec::from_array(e, [redeemer.clone().into_val(e)]);
        let digest = chimpdao_chip_auth::call_digest(
            e,
            DOMAIN,
            &e.current_contract_address(),
            &Symbol::new(e, "redeem"),
            &args,
            nonce,
        );
        let curve = shared_curve(nfc_client.curve(&public_key));
        if !chimpdao_chip_auth::verify_chip_auth(e, &digest, &public_key, &curve, auth) {
            panic_with_error!(e, &errors::PrizeError::InvalidSignature);
        }
        e.storage()
            .persistent()
            .set(&StorageKey::Nonce(public_key.clone()), &nonce);

        let token_id = nfc_client.token_id(&public_key);
        if nfc_client.owner_of(&token_id) != redeemer {
            panic_with_error!(e, &errors::PrizeError::NotChipOwner);
        }

        let key = StorageKey::Vault(public_key);
        let amount: i128 = e.storage().persistent().get(&key).unwrap_or(0i128);
        if amount <= 0 {
            panic_with_error!(e, &errors::PrizeError::NoVaultForChip);
        }
        e.storage().persistent().set(&key, &0i128);

        let token: Address = e.storage().instance().get(&DataKey::Token).unwrap();
        TokenClient::new(e, &token).transfer(&e.current_contract_address(), &redeemer, &amount);

        events::Redeem {
            token_id,
            amount,
            redeemer,
        }
        .publish(e);
    }

    fn get_redeemable(e: &Env, chip_public_key: BytesN<65>) -> i128 {
        e.storage()
            .persistent()
            .get(&StorageKey::Vault(chip_public_key))
            .unwrap_or(0i128)
    }

    fn get_nonce(e: &Env, public_key: BytesN<65>) -> u32 {
        e.storage()
            .persistent()
            .get(&StorageKey::Nonce(public_key))
            .unwrap_or(0u32)
    }
}
