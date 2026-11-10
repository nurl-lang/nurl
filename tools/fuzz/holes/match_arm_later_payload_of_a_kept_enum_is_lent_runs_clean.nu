// match_arm_later_payload_of_a_kept_enum_is_lent_runs_clean: the second, third and fourth payloads of a variant, of a `% Drop` type, bound in a `??` arm over an enum that someone keeps.
// Guard for agora #641: they are lent to the arm, as the first payload is (h231): the arm does not drop them, the enum's owner does, once. Before, the arm dropped a later payload at its end and the enum dropped it again: heap-use-after-free with no panic.
// main 6040c17: accepted, heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | runs-clean | - | agora #641 guard: later % Drop payloads of a kept enum (a temporary given an owner, a binding, a parameter) read in an arm and dropped once, with the enum
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb Four Bomb Bomb Bomb Bomb }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ mk4 → E { ^ @ E { Four ( bomb `4a` ) ( bomb `4b` ) ( bomb `4c` ) ( bomb `4d` ) } }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ look E e → v {
    ?? e {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( see `look` y ) }
        Four a b c d → { ( see `look` b ) ( see `look` d ) }
    }
}

@ last E e → Bomb {
    ?? e {
        Zero n → { ^ ( bomb `none` ) }
        Three x s y → { ^ y }
        Four a b c d → { ^ d }
    }
}

@ main → i {
    // a temporary the match gives an owner
    ?? ( mk3 ) {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( see `tmp` x ) ( see `tmp` y ) }
        Four a b c d → { ( nurl_println `four` ) }
    }
    ?? ( mk4 ) {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( nurl_println `three` ) }
        Four a b c d → { ( see `tmp` c ) }
    }
    // a binding, matched twice, then lent to a function that matches it
    : E e ( mk3 )
    ?? e {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( see `bound` y ) }
        Four a b c d → { ( nurl_println `four` ) }
    }
    ( look e )
    : E f ( mk4 )
    ( look f )
    // a later payload handed back: lent by the parameter it came out of
    : Bomb r ( last e )
    ( see `main` r )
    ( nurl_println `end` )
    ^ 0
}
