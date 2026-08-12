#![no_std]

//! Shared ChipAuth types + crypto for Pocket, nfc-nft, and chip-verifier.
//!
//! Digest/nonce ownership stays in the app contract. This crate owns k1 recover
//! and r1 IntAuth so we do not maintain three copies.
//!
//! Uses stable `Env::crypto()` only — not `crypto_hazmat` (unstable feature).

mod types;
mod verify;

pub use types::*;
pub use verify::*;
