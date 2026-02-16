use soroban_sdk::{Address, Bytes, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Upgrade {
    pub admin: Address,
    pub wasm_hash: Bytes,
}
