// enum_and_a_clone_of_its_payload_passed_to_one_resetting_call_runs_clean: AGORA-569 guard — `( reset_read o ( string_clone s ) )` - the enum and a copy of its payload handed to one call that resets the enum: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: `( reset_read o ( string_clone s ) )` - the enum and a copy of its payload handed to one call that resets the enum: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ reset_read inout Msg m String t → v {
    = m @ Msg { MNone }
    ( nurl_println ( string_data t ) )
}

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ( reset_read o ( string_clone s ) )
        }
        MNone → {}
    }
    ^ 0
}
