#![cfg(test)]

extern crate std;

use soroban_sdk::{
    Address, Env, IntoVal, Symbol,
    testutils::Address as _,
    token::{StellarAssetClient, TokenClient},
    vec,
};

use crate::{Call, Router, RouterClient};

fn sac<'a>(e: &'a Env, admin: &Address) -> (Address, TokenClient<'a>, StellarAssetClient<'a>) {
    let c = e.register_stellar_asset_contract_v2(admin.clone());
    let id = c.address();
    (
        id.clone(),
        TokenClient::new(e, &id),
        StellarAssetClient::new(e, &id),
    )
}

fn transfer(e: &Env, token: &Address, from: &Address, to: &Address, amount: i128) -> Call {
    Call {
        contract: token.clone(),
        method: Symbol::new(e, "transfer"),
        args: vec![e, from.into_val(e), to.into_val(e), amount.into_val(e)],
    }
}

/// The property the whole contract exists for: several contract calls, one transaction.
#[test]
fn executes_every_call_in_order() {
    let e = Env::default();
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let caller = Address::generate(&e);
    let a = Address::generate(&e);
    let b = Address::generate(&e);
    let (token, tok, mint) = sac(&e, &admin);
    mint.mint(&caller, &100);

    let router = RouterClient::new(&e, &e.register(Router, ()));
    router.batch(
        &caller,
        &vec![
            &e,
            transfer(&e, &token, &caller, &a, 30),
            transfer(&e, &token, &caller, &b, 20),
        ],
    );

    assert_eq!(tok.balance(&a), 30);
    assert_eq!(tok.balance(&b), 20);
    assert_eq!(tok.balance(&caller), 50);
}

/// A later leg may spend what an earlier one produced — the reason a move can be one
/// transaction at all. Run separately, this second transfer would fail on balance
/// until the first had landed.
#[test]
fn a_leg_can_spend_what_an_earlier_leg_delivered() {
    let e = Env::default();
    // `hop` authorizes below a root that `caller` invoked, so its authorization is not
    // tied to the root invocation. That is the same shape a cross-account move takes,
    // and it needs the host's non-root allowance — the local mirror of simulating with
    // `record_allow_nonroot`.
    e.mock_all_auths_allowing_non_root_auth();
    let admin = Address::generate(&e);
    let caller = Address::generate(&e);
    let hop = Address::generate(&e);
    let dest = Address::generate(&e);
    let (token, tok, mint) = sac(&e, &admin);
    mint.mint(&caller, &50);

    let router = RouterClient::new(&e, &e.register(Router, ()));
    router.batch(
        &caller,
        &vec![
            &e,
            transfer(&e, &token, &caller, &hop, 50),
            // `hop` starts empty; this only works because the leg above ran first.
            transfer(&e, &token, &hop, &dest, 50),
        ],
    );

    assert_eq!(tok.balance(&dest), 50);
    assert_eq!(tok.balance(&hop), 0);
}

/// All-or-nothing: a failing leg unwinds the legs that already succeeded. This is the
/// guarantee a sequence of separate transactions cannot give — without it an
/// interrupted position move strands value half-way.
#[test]
fn a_failing_leg_reverts_the_whole_batch() {
    let e = Env::default();
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let caller = Address::generate(&e);
    let a = Address::generate(&e);
    let (token, tok, mint) = sac(&e, &admin);
    mint.mint(&caller, &100);

    let router = RouterClient::new(&e, &e.register(Router, ()));
    let out = router.try_batch(
        &caller,
        &vec![
            &e,
            transfer(&e, &token, &caller, &a, 60),
            // More than the balance left after the first leg — must take it down too.
            transfer(&e, &token, &caller, &a, 60),
        ],
    );

    assert!(out.is_err());
    // The first transfer is gone as if it never happened.
    assert_eq!(tok.balance(&a), 0);
    assert_eq!(tok.balance(&caller), 100);
}

/// An empty batch is a no-op, not a panic — a caller composing a move should not have
/// to special-case "nothing to do".
#[test]
fn an_empty_batch_is_a_no_op() {
    let e = Env::default();
    e.mock_all_auths();
    let caller = Address::generate(&e);
    let router = RouterClient::new(&e, &e.register(Router, ()));
    router.batch(&caller, &vec![&e]);
}

/// The caller must authorize. Without the root `require_auth` the host would refuse a
/// recording simulation outright, and each sub-call would need its own signature.
#[test]
fn requires_the_caller_s_authorization() {
    let e = Env::default();
    let caller = Address::generate(&e);
    let router = RouterClient::new(&e, &e.register(Router, ()));
    // No `mock_all_auths` — nothing has authorized anything.
    assert!(router.try_batch(&caller, &vec![&e]).is_err());
}

/// The caller authorizes the batch itself, not merely the legs: a batch nobody
/// authorized must not run even when every leg would have been fine on its own.
#[test]
fn an_unauthorized_caller_moves_nothing() {
    let e = Env::default();
    e.mock_all_auths();
    let admin = Address::generate(&e);
    let caller = Address::generate(&e);
    let a = Address::generate(&e);
    let (token, tok, mint) = sac(&e, &admin);
    mint.mint(&caller, &100);

    let router = RouterClient::new(&e, &e.register(Router, ()));
    // Set-up is done; from here nothing is authorized.
    e.mock_auths(&[]);
    let out = router.try_batch(&caller, &vec![&e, transfer(&e, &token, &caller, &a, 10)]);

    assert!(out.is_err());
    assert_eq!(tok.balance(&a), 0);
    assert_eq!(tok.balance(&caller), 100);
}
