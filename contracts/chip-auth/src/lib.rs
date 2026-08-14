#![no_std]

//! Shared ChipAuth types + crypto for Pocket, the Pocket factory, nfc-nft, and
//! chip-verifier.
//!
//! Owns k1 recover and r1 IntAuth so we do not maintain three copies, plus the types
//! that cross a contract boundary (see `types`) so both sides stay XDR-identical.
//!
//! Uses stable `Env::crypto()` only — not `crypto_hazmat` (unstable feature).

mod types;
mod verify;

pub use types::*;
pub use verify::*;
