// enum_payload_read_after_the_enum_is_handed_to_a_later_callee_that_sinks_it: a `??` arm's String payload read after the matched enum binding was handed to a callee compiled after its caller, which hands it on to a `sink` (an inferred sink, known at module end).
// Closed with agora #641: a call row whose callee's final summary says it takes the argument moves the binding, and a binding handed over whole ends the payloads its arm bound (bck_cursor_follow), whichever row moved it.
// main c8c3f4d: accepted, heap-use-after-free in f (the callee drops the enum, the arm reads `s`).
// map: §2.10 | A2 | rejected | - | agora #641: a ?? payload of an enum binding read after the binding was handed to a callee compiled later that sinks it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ eat sink E e → v { ( nurl_println `eat` ) }

@ f → v {
    : E e ( mk3 )
    ?? e {
        Zero n → {}
        Three x s y → {
            ( later e )
            ( nurl_println ( string_data s ) )
        }
    }
}

@ later E e → v { ( eat e ) }

@ main → i {
    ( f )
    ^ 0
}
