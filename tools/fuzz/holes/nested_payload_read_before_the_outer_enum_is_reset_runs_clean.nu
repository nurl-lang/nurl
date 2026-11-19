// nested_payload_read_before_the_outer_enum_is_reset_runs_clean: AGORA-569 guard — a nested enum's payload read before the outer enum is reset by an inout callee: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: a nested enum's payload read before the outer enum is reset by an inout callee: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }
: | Outer { ONone OIn Msg }

@ reseto inout Outer m → v { = m @ Outer { ONone } }

@ main → i {
    : ~ Outer o @ Outer { OIn @ Msg { MSome ( string_from `the inner message string long enough for the heap` ) } }
    ?? o {
        OIn inner → {
            ?? inner {
                MSome s → {
                    ( nurl_println ( string_data s ) )
                    ( reseto o )
                }
                MNone → {}
            }
        }
        ONone → {}
    }
    ^ 0
}
