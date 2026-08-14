use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum SmartAccountError {
    /// Instance Chip missing (must be set at construct).
    InvalidChip = 200,

    /// Chip signature did not verify against the bound public key.
    InvalidSignature = 201,

    /// Instance Curve missing (must be set at construct).
    MissingCurve = 203,
}
