use soroban_sdk::{BytesN, contractevent};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CardAdded {
    pub key: BytesN<65>,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CardRemoved {
    pub key: BytesN<65>,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Abandoned {}
