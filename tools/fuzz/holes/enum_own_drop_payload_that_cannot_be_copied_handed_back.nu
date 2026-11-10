// enum_own_drop_payload_that_cannot_be_copied_handed_back: a `% Drop` payload of an enum with a `% Drop` of its own, handed back out of a `??` arm by the function that keeps the enum.
// Closed with agora #641: the enum stays whole for its destructor and drops its payloads after it; a payload that cannot be copied has no copy to give the caller, so the hand-back is refused. With the enum's glue alone, the caller and the enum both dropped it.
// main 37334be: accepted, the payloads leak (no glue).
// map: §7.6 | A2 | rejected | - | agora #641: a % Drop payload of a kept enum with its own % Drop handed back out of an arm (the enum drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

% Drop E { @ drop E e → v { ( nurl_println `drop E` ) } }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ first → Bomb {
    : E e ( mk3 )
    ?? e {
        Zero n → { ^ ( bomb `z` ) }
        Three x s y → { ^ x }
    }
}

@ main → i {
    : Bomb b ( first )
    ( nurl_println ( string_data . b tag ) )
    ^ 0
}
