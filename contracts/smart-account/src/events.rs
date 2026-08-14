use soroban_sdk::{Address, Symbol, contractevent};

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

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EarnLinked {
    #[topic]
    pub account: Address,
}

#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct EarnUnlinked {}

/// Lost-card recovery: the owner drained the purse float.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Swept {
    #[topic]
    pub token: Address,
    pub to: Address,
    pub amount: i128,
}

/// Holder changed their upgrade consent. Topic-indexed so the notification service can
/// find who still needs asking before a security push.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct UpgradePolicySet {
    #[topic]
    pub policy: crate::types::UpgradePolicy,
}
