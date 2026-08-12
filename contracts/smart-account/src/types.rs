use soroban_sdk::{contracttype, Address, Bytes, Map, Symbol};

// Re-export shared auth types for callers / tests (may be unused inside this crate).
#[allow(unused_imports)]
pub use chimpdao_chip_auth::{ChipAuth, Curve, Secp256k1Auth, Secp256r1Auth};

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    CollectionContract,
    Chip,
    Curve,
    Nonce,
    /// Pointer to linked Earn (Nido) account.
    Earn,
    /// Strategy inventory row keyed by strategy_id.
    Position(Symbol),
    /// Ordered list of strategy_ids that have a Position row.
    PositionIds,
}

/// On-chain pointer from Pocket → Earn (Nido) account.
#[derive(Clone)]
#[contracttype]
pub struct EarnLink {
    pub account: Address,
    pub context_rule_id: u32,
    pub verifier: Address,
}

/// Inventory row for a DeFi strategy opened for this chip (SoT for “what we have”).
#[derive(Clone)]
#[contracttype]
pub struct Position {
    pub strategy_id: Symbol,
    pub underlying: Address,
    pub meta: Map<Symbol, Bytes>,
    pub amount_hint: Option<i128>,
}
