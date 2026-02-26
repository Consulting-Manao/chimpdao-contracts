use soroban_sdk::{Address, Env, String, Vec, testutils::Address as _, vec};

use crate::{Collection, CollectionClient};

mod nfc_nft_contract {
    soroban_sdk::contractimport!(file = "../nfc_nft.wasm");
}

fn create_client<'a>(e: &Env, admin: &Address) -> CollectionClient<'a> {
    let address = e.register(Collection, (admin,));
    CollectionClient::new(e, &address)
}

#[test]
fn test_create_collection() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

    let wasm = e.deployer().upload_contract_wasm(nfc_nft_contract::WASM);

    let _collection_address = client.create_collection(
        &wasm,
        &String::from_str(&e, "TestNFT"),
        &String::from_str(&e, "TNFT"),
        &String::from_str(&e, "ipfs://abcd"),
        &10u32,
    );
}

#[test]
fn test_assign_collectible() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

    let wasm = e.deployer().upload_contract_wasm(nfc_nft_contract::WASM);

    let collection_a_address = client.create_collection(
        &wasm,
        &String::from_str(&e, "TestNFTA"),
        &String::from_str(&e, "TNFTA"),
        &String::from_str(&e, "ipfs://abcd"),
        &10u32,
    );

    let collection_b_address = client.create_collection(
        &wasm,
        &String::from_str(&e, "TestNFTB"),
        &String::from_str(&e, "TNFTB"),
        &String::from_str(&e, "ipfs://abcd"),
        &10u32,
    );

    let mando = Address::generate(&e);
    let grogu = Address::generate(&e);

    let collectibles = client.collectibles(&mando);
    assert_eq!(collectibles, Vec::new(&e));

    client.assign_collectible(&collection_a_address, &mando, &1u32);
    client.assign_collectible(&collection_a_address, &mando, &2u32);
    client.assign_collectible(&collection_b_address, &grogu, &1u32);
    client.assign_collectible(&collection_b_address, &mando, &2u32);

    let collectibles = client.collectibles(&mando);
    assert_eq!(
        collectibles,
        vec![
            &e,
            (collection_a_address.clone(), 1u32),
            (collection_a_address.clone(), 2u32),
            (collection_b_address.clone(), 2u32)
        ]
    );
    let collectibles = client.collectibles(&grogu);
    assert_eq!(collectibles, vec![&e, (collection_b_address.clone(), 1u32)]);

    // idempotent assignment
    client.assign_collectible(&collection_b_address, &grogu, &1u32);
    let collectibles = client.collectibles(&grogu);
    assert_eq!(collectibles, vec![&e, (collection_b_address.clone(), 1u32)]);

    // re-assign a token from mando to grogu
    client.assign_collectible(&collection_a_address, &grogu, &2u32);
    let collectibles = client.collectibles(&grogu);
    assert_eq!(
        collectibles,
        vec![
            &e,
            (collection_b_address.clone(), 1u32),
            (collection_a_address.clone(), 2u32),
        ]
    );
    let collectibles = client.collectibles(&mando);
    assert_eq!(
        collectibles,
        vec![
            &e,
            (collection_a_address.clone(), 1u32),
            (collection_b_address.clone(), 2u32)
        ]
    );
}
