use soroban_sdk::{
    contractimpl, panic_with_error, token::TokenClient, xdr::ToXdr, Address, Bytes, BytesN, Env,
    Symbol, Vec,
};

use crate::errors::SmartAccountError;
use crate::events;
use crate::types;
use crate::{SmartAccount, SmartAccountArgs, SmartAccountClient, SmartAccountTrait};

mod collection_contract {
    soroban_sdk::contractimport!(file = "../collection.wasm");
}

#[contractimpl]
impl SmartAccountTrait for SmartAccount {
    fn __constructor(
        e: &Env,
        collection_contract: Address,
        chip: BytesN<65>,
        curve: types::Curve,
    ) {
        e.storage()
            .instance()
            .set(&types::DataKey::CollectionContract, &collection_contract);
        e.storage().instance().set(&types::DataKey::Chip, &chip);
        e.storage().instance().set(&types::DataKey::Curve, &curve);
    }

    fn upgrade(
        e: &Env,
        wasm_hash: BytesN<32>,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn balance(e: &Env, token: Address) -> i128 {
        TokenClient::new(e, &token).balance(&e.current_contract_address())
    }

    fn transfer(
        e: &Env,
        token: Address,
        from: Address,
        to: Address,
        amount: i128,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        if amount <= 0 {
            panic_with_error!(e, SmartAccountError::InvalidAmount);
        }
        if from != e.current_contract_address() {
            panic_with_error!(e, SmartAccountError::InvalidChip);
        }

        Self::verify_chip_signature(e, from.clone().to_xdr(e), message, auth, nonce);

        TokenClient::new(e, &token).transfer(&from, &to, &amount);
    }

    fn get_nonce(e: &Env) -> u32 {
        e.storage()
            .persistent()
            .get(&types::DataKey::Nonce)
            .unwrap_or(0)
    }

    fn collection(e: &Env) -> Address {
        e.storage()
            .instance()
            .get(&types::DataKey::CollectionContract)
            .unwrap()
    }

    fn set_collection(
        e: &Env,
        collection_contract: Address,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );
        e.storage()
            .instance()
            .set(&types::DataKey::CollectionContract, &collection_contract);
    }

    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)> {
        let collection: Address = e
            .storage()
            .instance()
            .get(&types::DataKey::CollectionContract)
            .unwrap();
        collection_contract::Client::new(e, &collection).collectibles(&from)
    }

    fn get_earn(e: &Env) -> Option<types::EarnLink> {
        e.storage()
            .persistent()
            .get::<_, types::EarnLink>(&types::DataKey::Earn)
    }

    fn set_earn(
        e: &Env,
        link: types::EarnLink,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );
        e.storage().persistent().set(&types::DataKey::Earn, &link);
    }

    fn clear_earn(e: &Env, message: Bytes, auth: types::ChipAuth, nonce: u32) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );
        e.storage().persistent().remove(&types::DataKey::Earn);
    }

    fn get_positions(e: &Env) -> Vec<types::Position> {
        let ids: Vec<Symbol> = e
            .storage()
            .persistent()
            .get(&types::DataKey::PositionIds)
            .unwrap_or(Vec::new(e));
        let mut out = Vec::new(e);
        for id in ids.iter() {
            if let Some(p) = e
                .storage()
                .persistent()
                .get::<_, types::Position>(&types::DataKey::Position(id.clone()))
            {
                out.push_back(p);
            }
        }
        out
    }

    fn upsert_position(
        e: &Env,
        position: types::Position,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );

        let key = types::DataKey::Position(position.strategy_id.clone());
        let existed = e.storage().persistent().has(&key);
        e.storage().persistent().set(&key, &position);

        if !existed {
            let mut ids: Vec<Symbol> = e
                .storage()
                .persistent()
                .get(&types::DataKey::PositionIds)
                .unwrap_or(Vec::new(e));
            ids.push_back(position.strategy_id.clone());
            e.storage()
                .persistent()
                .set(&types::DataKey::PositionIds, &ids);
        }

        events::PositionUpserted {
            strategy_id: position.strategy_id,
            underlying: position.underlying,
        }
        .publish(e);
    }

    fn clear_position(
        e: &Env,
        strategy_id: Symbol,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        Self::verify_chip_signature(
            e,
            e.current_contract_address().to_xdr(e),
            message,
            auth,
            nonce,
        );

        let key = types::DataKey::Position(strategy_id.clone());
        e.storage().persistent().remove(&key);

        let ids: Vec<Symbol> = e
            .storage()
            .persistent()
            .get(&types::DataKey::PositionIds)
            .unwrap_or(Vec::new(e));
        let mut next = Vec::new(e);
        for id in ids.iter() {
            if id != strategy_id {
                next.push_back(id);
            }
        }
        e.storage()
            .persistent()
            .set(&types::DataKey::PositionIds, &next);

        events::PositionCleared { strategy_id }.publish(e);
    }
}

impl SmartAccount {
    /// Digest = sha256(message ‖ signer ‖ nonce_xdr). Verifies against Instance Chip.
    fn verify_chip_signature(
        e: &Env,
        signer: Bytes,
        message: Bytes,
        auth: types::ChipAuth,
        nonce: u32,
    ) {
        let public_key: BytesN<65> = e.storage().instance().get(&types::DataKey::Chip).unwrap();

        let curr_nonce: u32 = e
            .storage()
            .persistent()
            .get(&types::DataKey::Nonce)
            .unwrap_or(0);

        if nonce <= curr_nonce {
            panic_with_error!(&e, SmartAccountError::InvalidSignature);
        }

        let message_hash = chimpdao_chip_auth::message_digest(e, &message, &signer, nonce);
        let curve: types::Curve = e
            .storage()
            .instance()
            .get(&types::DataKey::Curve)
            .unwrap_or_else(|| panic_with_error!(&e, SmartAccountError::MissingCurve));

        if !chimpdao_chip_auth::verify_chip_auth(e, &message_hash, &public_key, &curve, auth) {
            panic_with_error!(&e, SmartAccountError::InvalidSignature);
        }

        e.storage().persistent().set(&types::DataKey::Nonce, &nonce);
    }
}
