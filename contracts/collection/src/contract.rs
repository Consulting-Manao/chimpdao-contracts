//! NFC Collection

use crate::{Collection, CollectionArgs, CollectionClient, CollectionTrait};
use soroban_sdk::{Address, BytesN, Env, String, Vec, contractimpl, contracttype};

#[contracttype]
pub enum DataKey {
    Admin,
}

#[contracttype]
pub enum CollectionKey {
    Collections,                // vec contract ID
    Collectibles(Address, u32), // (contract ID; Token ID) - Owner
    OwnerCollectibles(Address), // Owner - (contract ID; Token ID)
}

#[contractimpl]
impl CollectionTrait for Collection {
    fn __constructor(e: &Env, admin: Address) {
        e.storage().instance().set(&DataKey::Admin, &admin);
    }

    fn upgrade(e: &Env, wasm_hash: BytesN<32>) {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        e.deployer().update_current_contract_wasm(wasm_hash.clone());
    }

    fn create_collection(
        e: &Env,
        wasm_hash: BytesN<32>,
        name: String,
        symbol: String,
        uri: String,
        max_tokens: u32,
    ) -> Address {
        let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
        admin.require_auth();

        let salt: BytesN<32> = e.crypto().sha256(&symbol.to_bytes()).into();
        let deployer = e.deployer().with_current_contract(salt);
        let contract_address = deployer.deploy_v2(
            wasm_hash,
            (
                admin,
                e.current_contract_address(),
                name,
                symbol,
                uri,
                max_tokens,
            ),
        );

        let mut collections: Vec<Address> = e
            .storage()
            .instance()
            .get(&CollectionKey::Collections)
            .unwrap_or(Vec::new(e));
        collections.push_back(contract_address.clone());
        e.storage()
            .instance()
            .set(&CollectionKey::Collections, &collections);
        contract_address
    }

    fn assign_collectible(e: &Env, collection: Address, to: Address, token_id: u32) {
        collection.require_auth();

        let collectible = (collection.clone(), token_id);

        let owner_address: Option<Address> = e
            .storage()
            .instance()
            .get(&CollectionKey::Collectibles(collection.clone(), token_id));

        // transferring the collectible by removing from previous owner if any
        if let Some(owner_address) = owner_address {
            let mut owner_collectibles: Vec<(Address, u32)> = e
                .storage()
                .instance()
                .get(&CollectionKey::OwnerCollectibles(owner_address.clone()))
                .unwrap_or(Vec::new(e));
            let idx_collectible = owner_collectibles
                .first_index_of(collectible.clone())
                .unwrap();
            owner_collectibles.remove(idx_collectible);
            e.storage().instance().set(
                &CollectionKey::OwnerCollectibles(owner_address.clone()),
                &owner_collectibles,
            );
        }

        let mut owner_collectibles: Vec<(Address, u32)> = e
            .storage()
            .instance()
            .get(&CollectionKey::OwnerCollectibles(to.clone()))
            .unwrap_or(Vec::new(e));
        owner_collectibles.push_back(collectible);
        e.storage().instance().set(
            &CollectionKey::OwnerCollectibles(to.clone()),
            &owner_collectibles,
        );

        // set new owner
        e.storage().instance().set(
            &CollectionKey::Collectibles(collection.clone(), token_id),
            &to.clone(),
        );
    }

    fn collectibles(e: &Env, from: Address) -> Vec<(Address, u32)> {
        e.storage()
            .instance()
            .get(&CollectionKey::OwnerCollectibles(from.clone()))
            .unwrap_or(Vec::new(e))
    }
}
