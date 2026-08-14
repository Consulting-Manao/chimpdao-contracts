use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum PrizeError {
    /// No locked amount for this chip (redeem called with zero balance for the chip).
    NoVaultForChip = 400,
    /// Redeemer is not the current owner of the NFT for this chip.
    NotChipOwner = 401,
    /// Chip attestation did not verify, or the nonce was already used.
    InvalidSignature = 402,
    /// Non-positive deposit.
    InvalidAmount = 403,
}
