use soroban_sdk::{contracttype, BytesN};

#[derive(Clone, PartialEq, Eq)]
#[contracttype]
pub enum Curve {
    Secp256k1,
    Secp256r1,
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
