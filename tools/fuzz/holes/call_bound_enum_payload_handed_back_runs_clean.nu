// call_bound_enum_payload_handed_back_runs_clean: a payload of an enum that holds a `% Drop` value, bound from a call (`: E e ( mk )`), handed back out of a `??` arm by name and as a join's value — a String and a `% Drop` payload.
// Guard for agora #641: such a binding owns its value where the call's own answer says so (`@<slot>`), and gives a payload up there as a binding that always owns does (mem_enum_take): the payload moves out, the enum drops the rest. Before, no take was made through such a binding, the arm was lent the payload, and the caller got what the enum's drop then freed (a String) or dropped as well (a `% Drop` value).
// main 37334be: accepted, heap-use-after-free (in the caller for the String; in drop__Bomb for the Bomb).
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a payload handed back out of an enum bound from a call that answers per call is taken out of it where the binding owns (String and % Drop payloads, by name and as a join)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ the_string → String {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → { ^ s }
    }
    ^ ( string_from `none` )
}

@ the_string_joined → String {
    : E e ( mk )
    ^ ?? e {
        Zero n → ( string_from `none` )
        Three x s y → s
    }
}

@ the_bomb → Bomb {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → { ^ x }
    }
    ^ ( bomb `none` )
}

@ main → i {
    : String a ( the_string )
    ( nurl_println ( string_data a ) )
    : String b ( the_string_joined )
    ( nurl_println ( string_data b ) )
    : Bomb c ( the_bomb )
    ( nurl_println ( string_data . c tag ) )
    ^ 0
}
