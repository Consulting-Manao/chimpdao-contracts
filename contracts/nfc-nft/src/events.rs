use soroban_sdk::{Address, String, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Transfer {
    #[topic]
    pub from: Address,
    #[topic]
    pub to: Address,
    pub token_id: u32,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Mint {
    #[topic]
    pub to: Address,
    pub token_id: u32,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Claim {
    #[topic]
    pub claimant: Address,
    pub token_id: u32,
}

/// ERC-7496 `TraitMetadataURIUpdated`: the schema every cached trait is read through.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TraitMetadataUri {
    pub uri: String,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SetTrait {
    pub trait_key: String,
    pub token_id: u32,
    pub new_value: i128,
}
