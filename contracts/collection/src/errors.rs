use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum CollectionError {
    /// Indicates a non-existent `token_id`.
    NonExistentCollection = 300,
}