use soroban_sdk::{Address, BytesN, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CreateAccount {
    pub public_key: BytesN<65>,
    pub contract_address: Address,
}

/// Trail of every wasm ever put behind a chip address.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PocketWasmHashSet {
    #[topic]
    pub wasm_hash: BytesN<32>,
}
