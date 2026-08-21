use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum AccountError {
    /// Signature named a card this account does not list.
    UnknownCard = 300,
    /// Signature did not verify against the stored key and curve.
    InvalidSignature = 301,
    /// Card is already a signer here.
    DuplicateCard = 302,
    /// Refused: removing the last card would make the account unusable forever.
    /// Use `abandon` when that is genuinely intended.
    LastCard = 303,
    /// Constructed with an empty signer set.
    NoCards = 304,
}
