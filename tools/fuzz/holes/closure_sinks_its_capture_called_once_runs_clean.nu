// closure_sinks_its_capture_called_once_runs_clean: AGORA-479 guard — a closure body hands a sink its capture itself, called once: the closure gives the capture up when it runs, accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-479 guard: a closure body hands a sink its capture itself, called once: the closure gives the capture up when it runs, accepted
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { ^ ( eat x ) }
    ( nurl_println_int ( c ) )
    ^ 0
}
