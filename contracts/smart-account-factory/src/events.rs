use soroban_sdk::{Address, BytesN, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CreateAccount {
    pub public_key: BytesN<65>,
    pub contract_address: Address,
}
