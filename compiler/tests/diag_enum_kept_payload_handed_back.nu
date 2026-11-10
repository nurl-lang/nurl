// diag_enum_kept_payload_handed_back.nu — a `% Drop` payload of an enum
// the function keeps, handed back out of a `??` arm (Agora #641).
//
// `e` has a `% Drop` of its own: it stays whole for its destructor, which
// runs on the way out and then drops the payloads. The arm is lent `x`; a
// Bomb cannot be copied, so there is nothing to give the caller that the
// enum does not drop too.
$ `stdlib/core/string.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b tag ) ) } }

: | E { Zero i Two Bomb String }

% Drop E { @ drop E e → v { ( nurl_println `drop E` ) } }

@ first → Bomb {
    : E e @ E { Two @ Bomb { ( string_from `a` ) } ( string_from `s` ) }
    ?? e {
        Zero n → { ^ @ Bomb { ( string_from `z` ) } }
        Two x s → { ^ x }
    }
}

@ main → i {
    : Bomb b ( first )
    ^ 0
}
