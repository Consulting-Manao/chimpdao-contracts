use soroban_sdk::contracterror;

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum CollectionError {
    /// Indicates a non-existent collection address.
    NonExistentCollection = 300,
}
