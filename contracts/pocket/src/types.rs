use soroban_sdk::contracttype;

// Re-export shared types for callers / tests (may be unused inside this crate).
#[allow(unused_imports)]
pub use chimpdao_chip_auth::{ChipAuth, Curve, Secp256k1Auth, UpgradePolicy};

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    /// The bound card's 65-byte SEC1 public key.
    Chip,
    /// Which algorithm that key signs with. Stored so `__check_auth` verifies inline:
    /// delegating to a stored contract address would let whoever controls that pointer
    /// approve anything.
    Curve,
    /// Durable Chimp account behind this purse (lost-card recovery, handover).
    Owner,
    /// Whether the holder pre-consented to security upgrades.
    UpgradePolicy,
}
