use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum NonFungibleTokenError {
    /// Indicates an invalid signature
    InvalidSignature = 200,
    /// Indicates a non-existent `token_id`.
    NonExistentToken = 201,
    /// Indicates an error related to the ownership over a particular token.
    /// Used in transfers.
    IncorrectOwner = 202,
    /// Indicates all possible `token_id`s are already in use.
    TokenIDsAreDepleted = 203,
    /// Indicates the token was already minted.
    TokenAlreadyMinted = 210,
    /// Indicates the token was already claimed.
    TokenAlreadyClaimed = 211,
    /// Indicates the token exists but has not been claimed yet
    TokenNotClaimed = 212,
    /// Curve was not stored for this chip (must be set at mint).
    MissingCurve = 213,
    /// Destination account does not list this card as a signer (soulbound).
    NotCardHolder = 214,
    /// Unknown ERC-7496 trait key.
    TraitDoesNotExist = 216,
    /// `trait_values` was handed more keys than one call may batch.
    TooManyTraitKeys = 218,
}
