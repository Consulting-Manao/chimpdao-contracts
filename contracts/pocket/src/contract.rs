use soroban_sdk::{Address, BytesN, Env, contractimpl, token::TokenClient};

use crate::events;
use crate::types;
use crate::{Pocket, PocketArgs, PocketClient, PocketTrait};

/// `require_auth` on our own address routes to `__check_auth`, so the host binds the
/// arguments of whichever entry point called this.
fn require_chip(e: &Env) {
    e.current_contract_address().require_auth();
}

fn owner(e: &Env) -> Address {
    e.storage().instance().get(&types::DataKey::Owner).unwrap()
}

#[contractimpl]
impl PocketTrait for Pocket {
    fn __constructor(
        e: &Env,
        chip: BytesN<65>,
        curve: types::Curve,
        owner: Address,
        upgrade_policy: types::UpgradePolicy,
    ) {
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

    fn owner(e: &Env) -> Address {
        owner(e)
    }

    fn set_owner(e: &Env, new_owner: Address) {
        let current = owner(e);
        current.require_auth();
        e.storage()
            .instance()
            .set(&types::DataKey::Owner, &new_owner);
        events::OwnerChanged {
            old: current,
            new: new_owner,
        }
        .publish(e);
    }

    fn sweep(e: &Env, token: Address, to: Address) {
        let owner = owner(e);
        owner.require_auth();

        let client = TokenClient::new(e, &token);
        let amount = client.balance(&e.current_contract_address());
        if amount <= 0 {
            return;
        }
        client.transfer(&e.current_contract_address(), &to, &amount);

        events::Swept { token, to, amount }.publish(e);
    }
}
