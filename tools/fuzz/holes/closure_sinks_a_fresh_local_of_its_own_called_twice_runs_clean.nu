// closure_sinks_a_fresh_local_of_its_own_called_twice_runs_clean: AGORA-479 guard — a closure body that reads its capture hands a sink a String it makes itself, called twice: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-479 guard: a closure body that reads its capture hands a sink a String it makes itself, called twice: accepted
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : String x ( string_from `a captured string long enough for the heap buffer, surely` )
    : ( @ i ) c \ → i { : String y ( string_from `made in the body, long enough for the heap buffer` ) ^ + ( string_len x ) ( eat y ) }
    ( nurl_println_int ( c ) )
    ( nurl_println_int ( c ) )
    ^ 0
}
