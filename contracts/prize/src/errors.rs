use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum PrizeError {
    /// No locked amount for this chip (redeem called with zero balance for the chip).
    NoVaultForChip = 400,
    /// Redeemer is not the current owner of the NFT for this chip in the given NFC contract.
    NotChipOwner = 401,
}
