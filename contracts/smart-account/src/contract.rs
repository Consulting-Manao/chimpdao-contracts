use soroban_sdk::{Address, BytesN, Env, Symbol, Vec, contractimpl, token::TokenClient};

use crate::events;
use crate::types;
use crate::{SmartAccount, SmartAccountArgs, SmartAccountClient, SmartAccountTrait};

mod collection_contract {
    soroban_sdk::contractimport!(file = "../../target/wasm32v1-none/release/collection.wasm");
}

/// `require_auth` on our own address routes to `__check_auth`, so the host binds the
/// arguments of whichever entry point called this.
fn require_chip(e: &Env) {
    e.current_contract_address().require_auth();
}

#[contractimpl]
impl SmartAccountTrait for SmartAccount {
    fn __constructor(
        e: &Env,
        collection_contract: Address,
        chip: BytesN<65>,
        curve: types::Curve,
        owner: Address,
        upgrade_policy: types::UpgradePolicy,
    ) {
        e.storage()
            .instance()
            .set(&types::DataKey::CollectionContract, &collection_contract);
        e.storage().instance().set(&types::DataKey::Chip, &chip);
        e.storage().instance().set(&types::DataKey::Curve, &curve);
        e.storage().instance().set(&types::DataKey::Owner, &owner);
        e.storage()
            .instance()
            .set(&types::DataKey::UpgradePolicy, &upgrade_policy);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        require_chip(e);
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn upgrade_policy(e: &Env) -> types::UpgradePolicy {
        e.storage()
            .instance()
            .get(&types::DataKey::UpgradePolicy)
            .unwrap()
    }

    fn set_upgrade_policy(e: &Env, policy: types::UpgradePolicy) {
        require_chip(e);
        e.storage()
            .instance()
            .set(&types::DataKey::UpgradePolicy, &policy);
        events::UpgradePolicySet { policy }.publish(e);
    }

    fn balance(e: &Env, token: Address) -> i128 {
        TokenClient::new(e, &token).balance(&e.current_contract_address())
    }

    fn collection(e: &Env) -> Address {
        e.storage()
            .instance()
            .get(&types::DataKey::CollectionContract)
            .unwrap()
    }

    fn set_collection(e: &Env, collection_contract: Address) {
        require_chip(e);
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

    fn owner(e: &Env) -> Address {
        e.storage().instance().get(&types::DataKey::Owner).unwrap()
    }

    fn sweep(e: &Env, token: Address, to: Address) {
        let owner: Address = e.storage().instance().get(&types::DataKey::Owner).unwrap();
        owner.require_auth();

        let client = TokenClient::new(e, &token);
        let amount = client.balance(&e.current_contract_address());
        if amount <= 0 {
            return;
        }
        client.transfer(&e.current_contract_address(), &to, &amount);

        events::Swept { token, to, amount }.publish(e);
    }

    fn get_earn(e: &Env) -> Option<types::EarnLink> {
        e.storage()
            .persistent()
            .get::<_, types::EarnLink>(&types::DataKey::Earn)
    }

    fn set_earn(e: &Env, link: types::EarnLink) {
        require_chip(e);
        e.storage().persistent().set(&types::DataKey::Earn, &link);
        events::EarnLinked {
            account: link.account,
        }
        .publish(e);
    }

    fn clear_earn(e: &Env) {
        require_chip(e);
        e.storage().persistent().remove(&types::DataKey::Earn);
        events::EarnUnlinked {}.publish(e);
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

    fn upsert_position(e: &Env, position: types::Position) {
        require_chip(e);

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

    fn clear_position(e: &Env, strategy_id: Symbol) {
        require_chip(e);

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
