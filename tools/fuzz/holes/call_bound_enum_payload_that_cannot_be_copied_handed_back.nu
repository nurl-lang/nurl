// call_bound_enum_payload_that_cannot_be_copied_handed_back: a `% Drop` payload of an enum bound from a call (`: E e ( mk )`), handed back out of a `??` arm by the function that drops the enum.
// Closed with agora #641: the arm is lent the payload and the binding drops the enum, payloads and all, on the way out; a payload that cannot be copied has no copy to give the caller, so the hand-back is refused. Before, the caller's binding and the enum both dropped it.
// main 37334be: accepted, heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | rejected | - | agora #641: a % Drop payload of an enum bound from a call handed back out of an arm (the enum drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ the_bomb → Bomb {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → { ^ x }
    }
    ^ ( bomb `none` )
}

@ main → i {
    : Bomb c ( the_bomb )
    ( nurl_println ( string_data . c tag ) )
    ^ 0
}
