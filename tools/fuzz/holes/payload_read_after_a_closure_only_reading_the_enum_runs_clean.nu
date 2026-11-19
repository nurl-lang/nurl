// payload_read_after_a_closure_only_reading_the_enum_runs_clean: AGORA-569 guard — an enum arm's payload read after a closure that only reads the enum runs: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: an enum arm's payload read after a closure that only reads the enum runs: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    : ( @ i ) f \ → i { ?? o { MSome t → { ^ ( string_len t ) } MNone → { ^ 0 } } }
    ?? o {
        MSome s → {
            ( nurl_println_int ( f ) )
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}
