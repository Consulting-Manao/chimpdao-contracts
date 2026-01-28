use soroban_sdk::{testutils::Address as _, Address, Env};

use crate::{Collection, CollectionClient};

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
fn test_metadata() {
    let e = Env::default();
    e.mock_all_auths();

    let admin = Address::generate(&e);
    let client = create_client(&e, &admin);

}
