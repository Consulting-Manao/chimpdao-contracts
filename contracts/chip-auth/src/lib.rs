#![no_std]

//! Shared ChipAuth types + crypto, linked by every contract that has to check a chip
//! signature: `pocket`, `account` and `nfc-nft`.
//!
//! Owns k1 recover and r1 IntAuth so there is exactly one implementation of each, plus
//! the types that cross a contract boundary (see `types`) so both sides stay
//! XDR-identical. Linked rather than deployed: a verifier reached through a *stored
//! address* is a pointer someone can re-aim, which is a failure mode this crate's
//! callers no longer have.
//!
//! Uses stable `Env::crypto()` only — not `crypto_hazmat` (unstable feature).

mod types;
mod verify;

pub use types::*;
pub use verify::*;
