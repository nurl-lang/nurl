// enum_payload_read_after_the_enum_is_handed_to_a_sink: a `??` arm's String payload read after the matched enum binding was handed to a `sink` callee inside the arm.
// Closed with agora #641: the payload is read in place out of the enum, which the callee drops on its way out; a binding handed over whole ends the payloads its arm bound (`!epym`, bck_cursor_follow), as `= e …` already did and as an option's payload ends with its option. Found by the adversarial pass of #641 next to its own shape: with the drop glue an enum with a `% Drop` of its own reaches the same fault.
// main c8c3f4d: accepted, heap-use-after-free in main (the callee drops the enum, the arm reads `s`).
// map: §2.10 | A2 | rejected | - | agora #641: a ?? payload of an enum binding read after the binding was handed to a sink callee in the arm (the callee dropped the enum)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ eat sink E e → v { ( nurl_println `eat` ) }

@ main → i {
    : E e ( mk3 )
    ?? e {
        Zero n → {}
        Three x s y → {
            ( eat e )
            ( nurl_println ( string_data s ) )
        }
    }
    ^ 0
}
