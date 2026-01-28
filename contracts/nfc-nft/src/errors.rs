use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum NonFungibleTokenError {
    /// Indicates a non-existent `token_id`.
    NonExistentToken = 200,
    /// Indicates an error related to the ownership over a particular token.
    /// Used in transfers.
    IncorrectOwner = 201,
    /// Indicates overflow when adding two values
    MathOverflow = 205,
    /// Indicates all possible `token_id`s are already in use.
    TokenIDsAreDepleted = 206,
    /// Indicates an invalid amount to batch mint in `consecutive` extension.
    InvalidAmount = 207,
    /// Indicates the token was already minted.
    TokenAlreadyMinted = 210,
    /// Indicates the royalty amount is higher than 10_000 (100%) basis points.
    InvalidRoyaltyAmount = 212,
    /// Indicates an invalid signature
    InvalidSignature = 214,
    /// Indicates the token exists but has not been claimed yet
    TokenNotClaimed = 215,
}