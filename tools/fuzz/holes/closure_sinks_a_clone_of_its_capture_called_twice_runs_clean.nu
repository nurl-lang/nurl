// closure_sinks_a_clone_of_its_capture_called_twice_runs_clean: AGORA-479 guard — a closure body hands a sink a clone of its capture, called twice: the clone is the sink's own, accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-479 guard: a closure body hands a sink a clone of its capture, called twice: the clone is the sink's own, accepted
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { ^ ( eat ( string_clone x ) ) }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
