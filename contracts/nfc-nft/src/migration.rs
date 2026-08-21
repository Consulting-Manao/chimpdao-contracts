//! One-time mainnet migration entry points — **feature-gated, never shipped**.
//!
//! The mainnet deployment predates both the curve registry and the account stack:
//! `mint` took a raw `(message, signature, recovery_id)` and every token was claimed to
//! a classic G-address. The current contract needs a curve recorded per card, and its
//! `transfer` calls `has_card` / `add_card` / `remove_card` on both sides — all of which
//! trap against a G-address, so those tokens would be frozen.
//!
//! Both gaps are closed here, then this code is upgraded away. Build with
//! `--features migration`; the default build has no such entry points at all.

use crate::contract::{DataKey, NFTStorageKey};
use crate::{NFCtoNFT, NFCtoNFTArgs, NFCtoNFTClient, NFCtoNFTTrait};
use chimpdao_chip_auth::Curve;
use soroban_sdk::{Address, BytesN, Env, Vec, contractimpl};

fn require_admin(e: &Env) {
    let admin: Address = e.storage().instance().get(&DataKey::Admin).unwrap();
    admin.require_auth();
}

#[contractimpl]
impl NFCtoNFT {
    /// Record `Secp256k1` for cards minted before the curve registry existed.
    ///
    /// Every pre-curve card is an Infineon SECORA, so the curve is known rather than
    /// guessed. Idempotent: re-running overwrites with the same value.
    pub fn backfill_curves(e: &Env, public_keys: Vec<BytesN<65>>) {
        require_admin(e);
        for pk in public_keys.iter() {
            e.storage()
                .persistent()
                .set(&NFTStorageKey::ChipCurveByPublicKey(pk), &Curve::Secp256k1);
        }
    }

    /// Re-point a token from its legacy G-address owner to a Chimp account.
    ///
    /// The caller deploys the account first, seeded with `public_key(token_id)` as its
    /// sole card — so the holder's existing card keeps working and gains a transferable
    /// account without ever being tapped. Balances are moved with the token so
    /// `balance()` stays consistent.
    ///
    /// Deliberately does not verify a chip signature: the whole point is that these
    /// holders cannot be reached, and the admin already controls `clawback`.
    pub fn migrate_owner(e: &Env, token_id: u32, new_owner: Address) {
        require_admin(e);

        let current: Address = e
            .storage()
            .persistent()
            .get(&NFTStorageKey::Owner(token_id))
            .expect("token is claimed");
        if current == new_owner {
            return;
        }

        e.storage()
            .persistent()
            .set(&NFTStorageKey::Owner(token_id), &new_owner);

        let from_balance = Self::balance(e, current.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(current), &(from_balance - 1));
        let to_balance = Self::balance(e, new_owner.clone());
        e.storage()
            .persistent()
            .set(&NFTStorageKey::Balance(new_owner), &(to_balance + 1));
    }
}
