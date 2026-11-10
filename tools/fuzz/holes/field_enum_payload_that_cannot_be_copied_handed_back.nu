// field_enum_payload_that_cannot_be_copied_handed_back: a `% Drop` payload of an enum held in a field of a local struct, handed back out of a `??` arm (`?? . w en { Three x s y → { ^ x } }`).
// Closed with agora #641: the struct keeps the enum and drops it, payloads and all, on the way out; a payload that cannot be copied has no copy to give the caller, so the hand-back is refused. Before, the caller got the struct's own Bomb and both dropped it.
// main 37334be: accepted, heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | rejected | - | agora #641: a % Drop payload of an enum in a local struct's field handed back out of an arm (the struct drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

: W { E en i k }

@ mkw → W { ^ @ W { @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } 1 } }

@ first → Bomb {
    : W w ( mkw )
    ?? . w en {
        Zero n → { ^ ( bomb `z` ) }
        Three x s y → { ^ x }
    }
}

@ main → i {
    : Bomb b ( first )
    ( nurl_println ( string_data . b tag ) )
    ^ 0
}
