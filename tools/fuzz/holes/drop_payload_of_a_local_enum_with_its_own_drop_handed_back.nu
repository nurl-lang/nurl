// drop_payload_of_a_local_enum_with_its_own_drop_handed_back: a `% Drop` payload handed back out of an arm over a local enum with a `% Drop` of its own.
// Closed with agora #641: nothing is taken out of such an enum — its impl and then its glue drop it whole on the way out — so the payload is a view of the local, and a `% Drop` value cannot be copied: refused. Before, the payload was handed back as the caller's own while the enum kept it; with the enum's glue the caller would hold a value already dropped.
// main b444db1: accepted; `gb.c` is dropped by the caller and its box and the other payloads leak (no glue). Refused since github#1754 (c8c3f4d): a guard beside its probes.
// map: §7.6 | A2 | rejected | - | agora #641: a % Drop payload of a local enum with its own % Drop handed back from the arm (the enum's glue drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E2 { Zero2 i Three2 Bomb String Bomb One2 String }

% Drop E2 { @ drop E2 e → v { ( nurl_println `drop enum E2` ) } }

@ mk s a → E2 { ^ @ E2 { Three2 ( bomb ( nurl_str_cat a `.a` ) ) ( string_from `3s, long enough for the heap` ) ( bomb ( nurl_str_cat a `.c` ) ) } }

@ getb → Bomb {
    : E2 e ( mk `gb` )
    ?? e {
        Zero2 n → { ^ ( bomb `none` ) }
        Three2 x s y → { ^ y }
        One2 s → { ^ ( bomb `none` ) }
    }
}

@ main → i {
    : Bomb b ( getb )
    ( nurl_println ( string_data . b tag ) )
    ^ 0
}
