use soroban_sdk::{Address, contractevent};

/// Card handover: the purse re-pointed to a new account.
#[contractevent]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnerChanged {
    #[topic]
    pub old: Address,
    pub new: Address,
}

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
