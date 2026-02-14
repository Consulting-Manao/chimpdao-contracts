use soroban_sdk::{testutils::Address as _, Address, Env, String};

use crate::{Collection, CollectionClient};

mod nfc_nft_contract {
    soroban_sdk::contractimport!(file = "../nfc_nft.wasm");
}


fn create_client<'a>(e: &Env, admin: &Address) -> CollectionClient<'a> {
    let address = e.register(
        Collection,
        (
            admin,
        ),
    );
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
