// diag_own_drop_enum_param_payload_lent_and_sunk.nu — Agora #641: a
// payload handed back out of a by-value parameter, an enum with a `% Drop`
// of its own, is lent to the caller (nothing is taken out of such an enum).
// That holds while the caller keeps the enum. A function that also hands
// the parameter to a `sink` on another path takes it over — an inferred
// sink, known at module end — and drops it on every way out, so the lent
// payload would be read after the enum's drop glue released it. Refused,
// at the match; a parameter declared `sink` has its payload copied instead
// (`declared`, accepted).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | D { Dzero i Dthree Bomb String Bomb Done String }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ mkd → D { ^ @ D { Dthree ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ eat sink D d → v { ( nurl_println `eat` ) }

@ lent_and_sunk D d → String {
    ?? d {
        Dzero n → {}
        Dthree x s y → { ( eat d ) ^ ( string_from `sunk` ) }
        Done s → { ^ s }
    }
    ^ ( string_from `zero` )
}

@ declared sink D d → String {
    ?? d {
        Dzero n → {}
        Dthree x s y → { ^ s }
        Done s → { ^ s }
    }
    ^ ( string_from `zero` )
}

@ main → i {
    : String a ( lent_and_sunk ( mkd ) )
    ( nurl_println ( string_data a ) )
    : String b ( declared ( mkd ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
