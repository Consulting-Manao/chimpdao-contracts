use soroban_sdk::{BytesN, contracttype};

#[derive(Clone, PartialEq, Eq, Debug)]
#[contracttype]
pub enum Curve {
    Secp256k1,
    Secp256r1,
}

/// What a Pocket holder agreed to at onboarding. Here rather than in `pocket`
/// because the factory passes it to the Pocket constructor and a `cdylib` cannot be a
/// library dependency.
///
/// Both upgrade the same way today (`upgrade` is chip-authorized, one tap either way);
/// the difference is operational. Under CAP-85 `Managed` purses become fleet members
/// re-pointed by a tag owner.
#[derive(Clone, PartialEq, Eq, Debug)]
#[contracttype]
pub enum UpgradePolicy {
    /// Holder accepts security upgrades pushed by ChimpDAO.
    Managed,
    /// Holder is notified and taps to accept each upgrade.
    Manual,
}

#[derive(Clone)]
#[contracttype]
pub struct Secp256k1Auth {
    pub signature: BytesN<64>,
    pub recovery_id: u32,
}

#[derive(Clone)]
#[contracttype]
pub struct Secp256r1Auth {
    pub signature: BytesN<64>,
    pub rnd_b: BytesN<16>,
}

/// Complete chip proof for one gated call (Pocket / nfc-nft).
/// XDR-compatible with Earn `ChipSigData` field layout.
#[derive(Clone)]
#[contracttype]
pub enum ChipAuth {
    Secp256k1(Secp256k1Auth),
    Secp256r1(Secp256r1Auth),
}
