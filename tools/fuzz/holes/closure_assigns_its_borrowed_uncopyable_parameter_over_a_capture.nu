// closure_assigns_its_borrowed_uncopyable_parameter_over_a_capture: as closure_assigns_its_borrowed_parameter_over_a_capture_runs_clean, with a parameter whose type has a `% Drop` of its own and no copy.
// Refused: the parameter is lent for the call only and cannot be copied in, so the capture cannot be given it (agora #864).
// main's compiler: accepted; ASan reported heap-use-after-free reading the capture after the call.
// map: §2.11 | A2 | rejected | - | agora #864: a closure assigns its borrowed parameter with no copy over a by-pointer capture
$ `stdlib/core/string.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ once ( @ v Conn ) f → v {
    : Conn tmp @ Conn { ( string_from `a connection name long enough to live on the heap` ) }
    ( f tmp )
}

@ main → i {
    : ~ Conn best @ Conn { ( string_from `first` ) }
    ( once \ Conn r → v { = best r } )
    ( nurl_println ( string_data . best name ) )
    ^ 0
}
