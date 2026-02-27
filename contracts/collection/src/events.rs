use soroban_sdk::{Address, String, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CreateCollection {
    pub symbol: String,
    pub contract_address: Address,
}
