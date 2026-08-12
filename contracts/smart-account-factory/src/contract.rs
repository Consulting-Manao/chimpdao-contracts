use soroban_sdk::{contractimpl, contracttype, contracterror, panic_with_error, Address, Bytes, BytesN, Env};

use crate::events;
use crate::{
    Curve, SmartAccountFactory, SmartAccountFactoryArgs, SmartAccountFactoryClient,
    SmartAccountFactoryTrait,
};

#[contracttype]
pub enum DataKey {
    Admin,
    CollectionContract,
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
    MissingCollection = 1,
}

#[contractimpl]
impl SmartAccountFactoryTrait for SmartAccountFactory {
    fn __constructor(e: &Env, admin: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.deployer().update_current_contract_wasm(wasm_hash);
    }

    fn set_collection(e: &Env, collection_contract: Address) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();
        e.storage()
            .instance()
            .set(&DataKey::CollectionContract, &collection_contract);
    }

    fn collection(e: &Env) -> Option<Address> {
        e.storage().instance().get(&DataKey::CollectionContract)
    }

    fn create_account(
        e: &Env,
        wasm_hash: BytesN<32>,
        public_key: BytesN<65>,
        curve: Curve,
    ) -> Address {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        if let Some(existing) = Self::get_account(e, public_key.clone()) {
            return existing;
        }

        let Some(collection) = e
            .storage()
            .instance()
            .get::<_, Address>(&DataKey::CollectionContract)
        else {
            panic_with_error!(e, FactoryError::MissingCollection);
        };

        let pk_bytes: Bytes = public_key.clone().into();
        let salt: BytesN<32> = e.crypto().sha256(&pk_bytes).into();
        let contract_address = e.deployer().with_current_contract(salt).deploy_v2(
            wasm_hash,
            (admin, collection, public_key.clone(), curve),
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
