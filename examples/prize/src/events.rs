use soroban_sdk::{Address, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Deposit {
    pub nfc_contract: Address,
    pub token_id: u32,
    pub amount: i128,
    pub from: Address,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Redeem {
    pub nfc_contract: Address,
    pub token_id: u32,
    pub amount: i128,
    pub redeemer: Address,
}
