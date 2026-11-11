// drop_payload_of_a_matched_temporary_enum_with_its_own_drop_handed_back: a `% Drop` payload handed back out of an arm over a matched temporary (`?? ( mk ) { … }`) of an enum with a `% Drop` of its own.
// Closed with agora #641: the temporary has an owner now, which runs its impl and its glue on the way out, and nothing is taken out of such an enum: the payload is a view of the temporary, and a `% Drop` value cannot be copied — refused. Before, the temporary had no owner: the arm dropped its other `% Drop` payload as its own, the impl never ran, and the rest leaked; with an owner and the glue, the payload handed back would be dropped by the glue and again by the caller.
// main b444db1: accepted; the temporary has no owner: the arm drops `gb.a` as its own, the impl never runs, the caller owns `gb.c`, and the String payload and both boxes leak (LeakSanitizer). Refused since github#1754 (c8c3f4d): a guard beside its probes.
// map: §7.6 | A2 | rejected | - | agora #641: a % Drop payload of a matched temporary enum with its own % Drop handed back from the arm (the temporary's owner drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E2 { Zero2 i Three2 Bomb String Bomb One2 String }

% Drop E2 { @ drop E2 e → v { ( nurl_println `drop enum E2` ) } }

@ mk s a → E2 { ^ @ E2 { Three2 ( bomb ( nurl_str_cat a `.a` ) ) ( string_from `3s, long enough for the heap` ) ( bomb ( nurl_str_cat a `.c` ) ) } }

@ getb → Bomb {
    ?? ( mk `gb` ) {
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
