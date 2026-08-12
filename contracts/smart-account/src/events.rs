use soroban_sdk::{contractevent, Address, Symbol};

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PositionUpserted {
    #[topic]
    pub strategy_id: Symbol,
    pub underlying: Address,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PositionCleared {
    #[topic]
    pub strategy_id: Symbol,
}
