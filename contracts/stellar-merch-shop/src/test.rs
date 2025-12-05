extern crate std;

use soroban_sdk::{testutils::Address as _, Address, Env};
use crate::{StellarMerchShop, StellarMerchShopClient};

fn create_client<'a>(e: &Env, owner: &Address) -> StellarMerchShopClient<'a> {
    let address = e.register(StellarMerchShop, (owner,));
    StellarMerchShopClient::new(e, &address)
}

#[test]
fn something() {
    let e = Env::default();
    let admin = Address::generate(&e);
    // let client = create_client(&e, &admin);
    e.mock_all_auths();
}
