use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum SmartAccountError {
    InvalidChip = 200,
    /// Chip signature / nonce failed.
    InvalidSignature = 201,

    /// Non-positive transfer amount.
    InvalidAmount = 202,

    /// Instance Curve missing (must be set at construct).
    MissingCurve = 203,
}
