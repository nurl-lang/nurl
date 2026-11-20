// closure_inout_parameter_field_taken_and_refilled_runs_clean: AGORA-929 guard — a closure's own `inout` parameter has its field taken by a sink and given a value again before the closure returns: accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: a closure's inout parameter's taken field refilled before it returns
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : ( @ v inout Holder ) g \ inout Holder x → v {
        : i n ( take . x buf )
        = . x buf ( string_from `a new string for the holder, long enough for the heap buffer` )
    }
    ( g h )
    ( string_push_str . h buf ` appended` )
    ( nurl_println ( string_data . h buf ) )
    ^ 0
}
