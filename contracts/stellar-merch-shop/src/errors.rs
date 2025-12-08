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
    /// Indicates a failure with the `operator`s approval. Used in transfers.
    InsufficientApproval = 202,
    /// Indicates a failure with the `approver` of a token to be approved. Used
    /// in approvals.
    InvalidApprover = 203,
    /// Indicates an invalid value for `live_until_ledger` when setting
    /// approvals.
    InvalidLiveUntilLedger = 204,
    /// Indicates overflow when adding two values
    MathOverflow = 205,
    /// Indicates all possible `token_id`s are already in use.
    TokenIDsAreDepleted = 206,
    /// Indicates an invalid amount to batch mint in `consecutive` extension.
    InvalidAmount = 207,
    /// Indicates the token does not exist in owner's list.
    TokenNotFoundInOwnerList = 208,
    /// Indicates the token does not exist in global list.
    TokenNotFoundInGlobalList = 209,
    /// Indicates the token was already minted.
    TokenAlreadyMinted = 210,
    /// Indicates the length of the base URI exceeds the maximum allowed.
    BaseUriMaxLenExceeded = 211,
    /// Indicates the royalty amount is higher than 10_000 (100%) basis points.
    InvalidRoyaltyAmount = 212,
}