// enum_own_drop_payload_handed_back_runs_clean: a String payload of an enum with a `% Drop` of its own, handed back out of a `??` arm by a function that keeps the enum (a local, a temporary; by `^ s`, as a join's value, as a field of a boxed payload).
// Guard for agora #641: the enum stays whole for its destructor, which runs and then drops the payloads (its glue); what the arm hands back is the caller's own copy. Before the glue the payloads leaked (and the impl never ran for a temporary); with the glue alone the caller would have held what the enum freed.
// main 37334be: accepted, the payloads leak; `drop E` never printed for the temporary.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: a payload of an enum with its own % Drop handed back out of an arm is a copy; the enum's impl runs, then its payloads are dropped once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: Pair { Bomb p String q }

: | E { Zero i Three Bomb String Bomb Boxed Pair }

% Drop E { @ drop E e → v { ( nurl_println `drop E` ) } }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ by_name → String {
    : E e ( mk3 )
    ?? e {
        Zero n → {}
        Three x s y → { ^ s }
        Boxed p → {}
    }
    ^ ( string_from `none` )
}

@ by_join → String {
    : E e ( mk3 )
    ^ ?? e {
        Zero n → ( string_from `none` )
        Three x s y → s
        Boxed p → . p q
    }
}

@ of_temporary → String {
    ?? ( mk3 ) {
        Zero n → {}
        Three x s y → { ^ s }
        Boxed p → {}
    }
    ^ ( string_from `none` )
}

@ boxed_field → String {
    : E e @ E { Boxed @ Pair { ( bomb `bp` ) ( string_from `bq, long enough for the heap` ) } }
    ?? e {
        Zero n → {}
        Three x s y → {}
        Boxed p → { ^ . p q }
    }
    ^ ( string_from `none` )
}

@ main → i {
    : String a ( by_name )
    ( nurl_println ( string_data a ) )
    : String b ( by_join )
    ( nurl_println ( string_data b ) )
    : String c ( of_temporary )
    ( nurl_println ( string_data c ) )
    : String d ( boxed_field )
    ( nurl_println ( string_data d ) )
    ^ 0
}
