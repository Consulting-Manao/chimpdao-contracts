use soroban_sdk::{Address, contractevent, Bytes};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Upgrade {
    pub admin: Address,
    pub wasm_hash: Bytes,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Transfer {
    #[topic]
    pub from: Address,
    #[topic]
    pub to: Address,
    pub token_id: u64,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Mint {
    #[topic]
    pub token_id: u64,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Claim {
    #[topic]
    pub claimant: Address,
    pub token_id: u64,
}
