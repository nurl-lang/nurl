// payload_read_before_a_closure_assigns_the_enum_runs_clean: AGORA-569 guard — an enum arm's payload read before a closure that assigns the enum runs: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: an enum arm's payload read before a closure that assigns the enum runs: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    : ( @ v ) f \ → v { = o @ Msg { MNone } }
    ?? o {
        MSome s → {
            ( nurl_println ( string_data s ) )
            ( f )
        }
        MNone → {}
    }
    ^ 0
}
