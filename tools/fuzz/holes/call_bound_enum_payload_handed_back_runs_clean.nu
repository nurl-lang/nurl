// call_bound_enum_payload_handed_back_runs_clean: a String payload of an enum that holds a `% Drop` value, bound from a call (`: E e ( mk )`), handed back out of a `??` arm by name and as a join's value.
// Guard for agora #641: such a binding owns its value where the call's own answer says so (`@<slot>`), no take moves a payload out of it, and the arm is lent the payload: handed back, the caller gets its own copy where the binding owns the enum (__payload_keeper_flag). Before, the caller got the String the enum's drop then freed.
// main 37334be: accepted, heap-use-after-free in the caller.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a String payload handed back out of an enum bound from a call that answers per call is the caller's own copy (by name and as a join)
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

@ main → i {
    : String a ( the_string )
    ( nurl_println ( string_data a ) )
    : String b ( the_string_joined )
    ( nurl_println ( string_data b ) )
    ^ 0
}
