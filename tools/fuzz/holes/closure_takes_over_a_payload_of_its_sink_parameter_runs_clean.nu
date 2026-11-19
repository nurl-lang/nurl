// closure_takes_over_a_payload_of_its_sink_parameter_runs_clean: AGORA-479 guard — a closure over a `sink` parameter hands a sink its payload, called once: the frame owns the parameter, the takeover stands, accepted
// map: §7.5 | A2 | runs-clean | - | AGORA-479 guard: a closure over a sink parameter hands a sink its payload, called once
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ use sink ? String o → i {
    : ( @ i ) c \ → i { ?? o { T s → { ^ ( eat s ) } F → { ^ 0 } } }
    ^ ( c )
}

@ main → i {
    : ?String x @ ?String { T ( string_from `a caller option long enough for the heap buffer, surely` ) }
    ( nurl_println_int ( use x ) )
    ^ 0
}
