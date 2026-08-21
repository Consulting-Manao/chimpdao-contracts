use soroban_sdk::{
    Address, Bytes, BytesN, Env, contracterror, contractimpl, contracttype, panic_with_error,
};

use crate::events;
use crate::{
    Curve, PocketFactory, PocketFactoryArgs, PocketFactoryClient, PocketFactoryTrait, UpgradePolicy,
};

#[contracttype]
pub enum DataKey {
    Admin,
    /// The one Pocket wasm this factory may deploy. Pinned in state rather than passed
    /// per call, so the code behind every chip address is a single auditable value —
    /// and the natural home for a CAP-85 executable tag once Protocol 28 lands.
    PocketWasmHash,
}

#[contracttype]
pub enum AccountKey {
    /// Chip SEC1 pubkey → Pocket C-address.
    Account(BytesN<65>),
}

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum FactoryError {
    MissingWasmHash = 2,
}

fn require_admin(e: &Env) -> Address {
    let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
    admin.require_auth();
    admin
}

#[contractimpl]
impl PocketFactoryTrait for PocketFactory {
    fn __constructor(e: &Env, admin: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        require_admin(e);
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn set_pocket_wasm_hash(e: &Env, wasm_hash: BytesN<32>) {
        require_admin(e);
        e.storage()
            .instance()
            .set(&DataKey::PocketWasmHash, &wasm_hash);
        events::PocketWasmHashSet { wasm_hash }.publish(e);
    }

    fn pocket_wasm_hash(e: &Env) -> Option<BytesN<32>> {
        e.storage().instance().get(&DataKey::PocketWasmHash)
    }

    fn create_account(
        e: &Env,
        public_key: BytesN<65>,
        curve: Curve,
        owner: Address,
        upgrade_policy: UpgradePolicy,
    ) -> Address {
        require_admin(e);

        if let Some(existing) = Self::get_account(e, public_key.clone()) {
            return existing;
        }

        let Some(wasm_hash) = e
            .storage()
            .instance()
            .get::<_, BytesN<32>>(&DataKey::PocketWasmHash)
        else {
            panic_with_error!(e, FactoryError::MissingWasmHash);
        };

        let pk_bytes: Bytes = public_key.clone().into();
        let salt: BytesN<32> = e.crypto().sha256(&pk_bytes).into();
        let contract_address = e.deployer().with_current_contract(salt).deploy_v2(
            wasm_hash,
            (public_key.clone(), curve, owner, upgrade_policy),
        );

        e.storage()
            .persistent()
            .set(&AccountKey::Account(public_key.clone()), &contract_address);

        events::CreateAccount {
            public_key,
            contract_address: contract_address.clone(),
        }
        .publish(e);

        contract_address
    }

    fn get_account(e: &Env, public_key: BytesN<65>) -> Option<Address> {
        e.storage()
            .persistent()
            .get(&AccountKey::Account(public_key))
    }
}
