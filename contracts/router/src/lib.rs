//! Atomic multi-call, so a DeFi position can be **moved** in one transaction.
//!
//! Soroban allows exactly one `InvokeHostFunction` operation per transaction, so a move
//! spanning several contracts — close the position here, carry the assets across,
//! reopen it there — could otherwise only be a sequence of separate transactions. That
//! sequence has a real failure mode: each leg is valid only once the previous one has
//! landed, so an interruption leaves the holder's value liquid and the position
//! half-moved. Routing every leg through one `batch` call makes the whole move
//! all-or-nothing.
//!
//! **The `caller.require_auth()` below is the entire point of this contract**, and it
//! is not ceremony. Soroban builds one *condensed authorization tree per address*: the
//! nodes where that address's `require_auth` fired. Without a root `require_auth` a
//! caller's authorizations across N sub-calls form N disjoint trees — N authorization
//! entries, N signatures, and a recording simulation that refuses outright. Anchoring
//! the tree here merges them: **one entry, one nonce, one payload, one chip signature**
//! for the whole batch.
//!
//! A batch may still legitimately carry a second entry, because a position move spans
//! two accounts: the source closes, the destination reopens, and the destination's
//! `require_auth` fires below a root the source called. That is a *non-root*
//! authorization — the caller must simulate with `record_allow_nonroot` and sign each
//! returned entry. One card can produce both signatures, since it owns the purse and
//! sits on the account.
//!
//! The router is pure pass-through. It never holds funds, keeps no state but its own
//! liveness, has no admin and no upgrade path, and grants nothing: a sub-call moves
//! value only because the caller passed its own address as that call's `from`, and the
//! token's `require_auth` is satisfied by a node in the caller's own tree. There is
//! deliberately no allowance model to abuse and nothing here to re-point.
//!
//! Failure is all-or-nothing by construction: `invoke_contract` propagates a panic, so a
//! failing leg unwinds every earlier leg with it. There is no try-and-continue variant —
//! a partially-applied position move is precisely the state this contract prevents.

#![no_std]

use soroban_sdk::{Address, Env, Symbol, Val, Vec, contract, contractimpl, contracttype};

/// Roughly one day of ledgers at ~5s each — the unit the thresholds below are built from.
const LEDGERS_PER_DAY: u32 = 17_280;
/// Below a month of remaining life, top the instance back up to a quarter. The router
/// is stateless, so its instance entry is the only thing that can expire, and every
/// call is a natural heartbeat: a router in use never lapses, and one nobody calls is
/// allowed to.
const TTL_FLOOR: u32 = LEDGERS_PER_DAY * 30;
const TTL_TARGET: u32 = LEDGERS_PER_DAY * 90;

/// One leg of a batch. Named fields rather than a bare tuple so the intent survives
/// into the contract spec and any generated bindings.
#[contracttype]
#[derive(Clone)]
pub struct Call {
    pub contract: Address,
    pub method: Symbol,
    pub args: Vec<Val>,
}

#[contract]
pub struct Router;

#[contractimpl]
impl Router {
    /// Invoke every call in order, as `caller`, in a single transaction.
    ///
    /// Return values are deliberately not propagated: nothing needs them (a caller that
    /// wants a leg's result can read it from the simulation), and dropping them keeps
    /// the batch's own footprint to what the legs themselves require.
    pub fn batch(e: Env, caller: Address, calls: Vec<Call>) {
        // Anchors every sub-authorization into one tree — see the module docs.
        caller.require_auth();
        e.storage().instance().extend_ttl(TTL_FLOOR, TTL_TARGET);

        for call in calls.iter() {
            e.invoke_contract::<Val>(&call.contract, &call.method, call.args);
        }
    }
}

mod test;
