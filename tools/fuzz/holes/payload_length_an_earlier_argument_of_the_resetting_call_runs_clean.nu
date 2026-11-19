// payload_length_an_earlier_argument_of_the_resetting_call_runs_clean: AGORA-569 guard — `( show ( string_len s ) ( reset_ret o ) )` - a number read out of the payload before the call that resets the enum: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-569 guard: `( show ( string_len s ) ( reset_ret o ) )` - a number read out of the payload before the call that resets the enum: accepted
$ `stdlib/core/string.nu`

: | Msg { MNone MSome String }

@ reset_ret inout Msg m → i { = m @ Msg { MNone } ^ 0 }

@ show i n i k → v { ( nurl_println_int n ) }

@ main → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ( show ( string_len s ) ( reset_ret o ) )
        }
        MNone → {}
    }
    ^ 0
}
