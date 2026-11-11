// diag_enum_kept_payload_field_handed_back.nu — a `% Drop` field of a
// boxed payload of an enum the function keeps, handed back out of a `??`
// arm (Agora #641).
//
// `e` has a `% Drop` of its own: it stays whole for its destructor, which
// runs on the way out and then drops the payload, fields and all. The arm
// is lent `p`; a Bomb cannot be copied, so there is nothing to give the
// caller that the enum does not drop too.
$ `stdlib/core/string.nu`

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b tag ) ) } }

: Pair { Bomb b String q }

: | E { Zero i Boxed Pair }

% Drop E { @ drop E e → v { ( nurl_println `drop E` ) } }

@ first → Bomb {
    : E e @ E { Boxed @ Pair { @ Bomb { ( string_from `a` ) } ( string_from `q` ) } }
    ?? e {
        Zero n → { ^ @ Bomb { ( string_from `z` ) } }
        Boxed p → { ^ . p b }
    }
}

@ main → i {
    : Bomb b ( first )
    ^ 0
}
