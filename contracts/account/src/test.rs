//! Signer-set management and its guards. The signature paths are proven on live
//! hardware (testnet txs from chimpdao-terminal), not simulated here.
#![cfg(test)]

extern crate std;

use chimpdao_chip_auth::Curve;
use soroban_sdk::{BytesN, Env, Vec, vec};

use crate::{CardSigner, ChimpAccount, ChimpAccountClient};

fn card(e: &Env, fill: u8, curve: Curve) -> CardSigner {
    CardSigner {
        key: BytesN::from_array(e, &[fill; 65]),
        curve,
    }
}

fn client<'a>(e: &Env, cards: Vec<CardSigner>) -> ChimpAccountClient<'a> {
    e.mock_all_auths();
    let id = e.register(ChimpAccount, (cards,));
    ChimpAccountClient::new(e, &id)
}

#[test]
fn founding_card_is_a_signer() {
    let e = Env::default();
    let a = card(&e, 1, Curve::Secp256k1);
    let c = client(&e, vec![&e, a.clone()]);

    assert_eq!(c.cards().len(), 1);
    assert!(c.has_card(&a.key));
    assert!(!c.has_card(&BytesN::from_array(&e, &[9u8; 65])));
}

#[test]
fn cards_are_interchangeable_and_keep_their_curve() {
    let e = Env::default();
    let k1 = card(&e, 1, Curve::Secp256k1);
    let r1 = card(&e, 2, Curve::Secp256r1);
    let c = client(&e, vec![&e, k1.clone()]);

    c.add_card(&r1);

    // 1-of-n: both are signers, each remembering its own algorithm.
    assert!(c.has_card(&k1.key) && c.has_card(&r1.key));
    let stored = c.cards();
    assert_eq!(stored.get(0).unwrap().curve, Curve::Secp256k1);
    assert_eq!(stored.get(1).unwrap().curve, Curve::Secp256r1);
}

#[test]
fn removing_a_card_leaves_the_others() {
    let e = Env::default();
    let a = card(&e, 1, Curve::Secp256k1);
    let b = card(&e, 2, Curve::Secp256k1);
    let c = client(&e, vec![&e, a.clone(), b.clone()]);

    c.remove_card(&a.key);

    assert!(!c.has_card(&a.key));
    assert!(c.has_card(&b.key));
}

#[test]
#[should_panic(expected = "Error(Contract, #303)")]
fn the_last_card_cannot_be_removed() {
    let e = Env::default();
    let a = card(&e, 1, Curve::Secp256k1);
    let c = client(&e, vec![&e, a.clone()]);

    // An account with no signer could never authorize adding one back.
    c.remove_card(&a.key);
}

#[test]
fn abandon_is_the_explicit_way_to_empty_an_account() {
    let e = Env::default();
    let a = card(&e, 1, Curve::Secp256k1);
    let c = client(&e, vec![&e, a.clone()]);

    c.abandon();

    assert_eq!(c.cards().len(), 0);
    assert!(!c.has_card(&a.key));
}

#[test]
#[should_panic(expected = "Error(Contract, #302)")]
fn a_duplicate_card_is_rejected() {
    let e = Env::default();
    let a = card(&e, 1, Curve::Secp256k1);
    let c = client(&e, vec![&e, a.clone()]);

    c.add_card(&a);
}

#[test]
#[should_panic(expected = "Error(Contract, #300)")]
fn removing_an_unlisted_card_is_rejected() {
    let e = Env::default();
    let c = client(
        &e,
        vec![
            &e,
            card(&e, 1, Curve::Secp256k1),
            card(&e, 2, Curve::Secp256k1),
        ],
    );

    c.remove_card(&BytesN::from_array(&e, &[9u8; 65]));
}

#[test]
#[should_panic(expected = "Error(Contract, #304)")]
fn an_account_cannot_be_created_with_no_signer() {
    let e = Env::default();
    e.mock_all_auths();
    let empty: Vec<CardSigner> = Vec::new(&e);
    e.register(ChimpAccount, (empty,));
}

// --- wire format ------------------------------------------------------------
//
// The terminal hand-builds these envelopes (`scCardSigner` / `accountChipSignature` in
// chimpdao-terminal/src/chain/chip-auth.ts) rather than going through generated
// bindings, so nothing else would catch a drift in field order or variant naming — a
// mismatch shows up only as an opaque auth failure on live hardware. These are the
// exact bytes that client emits.

/// `Vec<CardSigner>` as `__constructor` receives it from `deployAccount`.
const TERMINAL_VEC_CARDS: &str = "AAAAEAAAAAEAAAABAAAAEQAAAAEAAAACAAAADwAAAAVjdXJ2ZQAAAAAAABAAAAABAAAAAQAAAA8AAAAJU2VjcDI1NmsxAAAAAAAADwAAAANrZXkAAAAADQAAAEEEAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QAAAAA==";

/// `CardSigner` on the r1 curve — `add_card` from the terminal.
const TERMINAL_CARD_R1: &str = "AAAAEQAAAAEAAAACAAAADwAAAAVjdXJ2ZQAAAAAAABAAAAABAAAAAQAAAA8AAAAJU2VjcDI1NnIxAAAAAAAADwAAAANrZXkAAAAADQAAAEEEAQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QAAAAA==";

/// `AccountAuth { key, auth: ChipAuth::Secp256k1(..) }` — what `__check_auth` is handed.
const TERMINAL_ACCOUNT_AUTH_K1: &str = "AAAAEQAAAAEAAAACAAAADwAAAARhdXRoAAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2azEAAAAAAAARAAAAAQAAAAIAAAAPAAAAC3JlY292ZXJ5X2lkAAAAAAMAAAABAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQMjHxsXEw8LBwL++vby7urm4t7a1tLOysbCvrq2sq6qpqKempaSjoqGgn56dnJuamZiXlpWUk5KRkI+OjYyLiokAAAAPAAAAA2tleQAAAAANAAAAQQQBAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AAAAA";

/// The same, on the r1 curve (`ChipAuth::Secp256r1 { rnd_b, signature }`).
const TERMINAL_ACCOUNT_AUTH_R1: &str = "AAAAEQAAAAEAAAACAAAADwAAAARhdXRoAAAAEAAAAAEAAAACAAAADwAAAAlTZWNwMjU2cjEAAAAAAAARAAAAAQAAAAIAAAAPAAAABXJuZF9iAAAAAAAADQAAABCgoaKjpKWmp6ipqqusra6vAAAADwAAAAlzaWduYXR1cmUAAAAAAAANAAAAQMjHxsXEw8LBwL++vby7urm4t7a1tLOysbCvrq2sq6qpqKempaSjoqGgn56dnJuamZiXlpWUk5KRkI+OjYyLiokAAAAPAAAAA2tleQAAAAANAAAAQQQBAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj9AAAAA";

fn decode<T>(e: &Env, b64: &str) -> T
where
    T: soroban_sdk::TryFromVal<Env, soroban_sdk::Val>,
{
    use soroban_sdk::TryIntoVal;
    use soroban_sdk::xdr::{Limits, ReadXdr, ScVal};
    let sc = ScVal::from_xdr_base64(b64, Limits::none()).expect("not valid ScVal XDR");
    let val: soroban_sdk::Val = sc.try_into_val(e).expect("ScVal is not a host Val");
    T::try_from_val(e, &val).unwrap_or_else(|_| panic!("wrong shape for this type"))
}

/// The terminal's 65-byte SEC1 filler: `04` then `01..40`.
fn terminal_key(e: &Env) -> BytesN<65> {
    let mut raw = [0u8; 65];
    raw[0] = 0x04;
    for (i, b) in raw.iter_mut().enumerate().skip(1) {
        *b = i as u8;
    }
    BytesN::from_array(e, &raw)
}

#[test]
fn terminal_constructor_args_decode_as_cards() {
    let e = Env::default();
    let cards: Vec<CardSigner> = decode(&e, TERMINAL_VEC_CARDS);

    assert_eq!(cards.len(), 1);
    let card = cards.get_unchecked(0);
    assert_eq!(card.key, terminal_key(&e));
    assert_eq!(card.curve, Curve::Secp256k1);
}

#[test]
fn terminal_card_signer_decodes_on_both_curves() {
    let e = Env::default();
    let r1: CardSigner = decode(&e, TERMINAL_CARD_R1);

    assert_eq!(r1.key, terminal_key(&e));
    assert_eq!(r1.curve, Curve::Secp256r1);
}

#[test]
fn terminal_account_auth_decodes_on_both_curves() {
    use crate::AccountAuth;
    use chimpdao_chip_auth::ChipAuth;

    let e = Env::default();

    let k1: AccountAuth = decode(&e, TERMINAL_ACCOUNT_AUTH_K1);
    assert_eq!(k1.key, terminal_key(&e));
    match k1.auth {
        ChipAuth::Secp256k1(a) => {
            assert_eq!(a.recovery_id, 1);
            assert_eq!(a.signature.len(), 64);
        }
        _ => panic!("k1 envelope decoded as the wrong variant"),
    }

    let r1: AccountAuth = decode(&e, TERMINAL_ACCOUNT_AUTH_R1);
    assert_eq!(r1.key, terminal_key(&e));
    match r1.auth {
        ChipAuth::Secp256r1(a) => {
            assert_eq!(a.rnd_b.len(), 16);
            assert_eq!(a.signature.len(), 64);
        }
        _ => panic!("r1 envelope decoded as the wrong variant"),
    }
}
