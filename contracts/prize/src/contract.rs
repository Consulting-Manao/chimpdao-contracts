//! Prize contract implementation.
//!
//! Lock token (e.g. XLM) per chip public key; redeems require chip signature
//! verification and NFT ownership via a bound NFC-NFT contract.

use crate::{Prize, PrizeArgs, PrizeClient, PrizeTrait, errors, events, nfc_contract};
use soroban_sdk::xdr::ToXdr;
use soroban_sdk::{
    Address, Bytes, BytesN, Env, contractimpl, contracttype, panic_with_error, token::TokenClient,
};

#[contracttype]
pub enum DataKey {
    Admin,
    Token,
}

#[contracttype]
pub enum StorageKey {
    Vault(BytesN<65>),
}

#[contractimpl]
impl PrizeTrait for Prize {
    fn __constructor(e: &Env, admin: Address, token: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
        e.storage().instance().set(&DataKey::Token, &token);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn deposit(e: &Env, from: Address, amount: i128, nfc_contract: Address, token_id: u32) {
        from.require_auth();

        let token: Address = e.storage().instance().get(&DataKey::Token).unwrap();
        let contract = e.current_contract_address();
        TokenClient::new(e, &token).transfer(&from, &contract, &amount);

        let nfc_client = nfc_contract::Client::new(e, &nfc_contract);
        let chip_public_key = nfc_client.public_key(&token_id);
        let key = StorageKey::Vault(chip_public_key.clone());
        let current: i128 = e.storage().persistent().get(&key).unwrap_or(0i128);
        e.storage().persistent().set(&key, &(current + amount));

        events::Deposit {
            nfc_contract,
            token_id,
            amount,
            from,
        }
        .publish(e);
    }

    #[allow(clippy::too_many_arguments)]
    fn redeem(
        e: &Env,
        redeemer: Address,
        nfc_contract: Address,
        message: Bytes,
        signature: BytesN<64>,
        recovery_id: u32,
        public_key: BytesN<65>,
        nonce: u32,
    ) {
        redeemer.require_auth();

        let nfc_client = nfc_contract::Client::new(e, &nfc_contract);

        let signer = redeemer.clone().to_xdr(e);
        nfc_client.verify_chip_signature(
            &signer,
            &message,
            &signature,
            &recovery_id,
            &public_key,
            &nonce,
        );

        let token_id = nfc_client.token_id(&public_key);
        let owner = nfc_client.owner_of(&token_id);
        if owner != redeemer {
            panic_with_error!(&e, &errors::PrizeError::NotChipOwner);
        }

        let key = StorageKey::Vault(public_key.clone());
        let amount: i128 = e.storage().persistent().get(&key).unwrap_or(0i128);
        if amount <= 0 {
            panic_with_error!(&e, &errors::PrizeError::NoVaultForChip);
        }

        e.storage().persistent().set(&key, &0i128);

        let token: Address = e.storage().instance().get(&DataKey::Token).unwrap();
        let contract = e.current_contract_address();
        TokenClient::new(e, &token).transfer(&contract, &redeemer, &amount);

        events::Redeem {
            nfc_contract,
            token_id,
            amount,
            redeemer,
        }
        .publish(e);
    }

    fn get_redeemable(e: &Env, chip_public_key: BytesN<65>) -> i128 {
        let key = StorageKey::Vault(chip_public_key);
        e.storage().persistent().get(&key).unwrap_or(0i128)
    }
}
