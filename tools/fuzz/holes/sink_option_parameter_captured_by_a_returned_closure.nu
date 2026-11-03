// sink_option_parameter_captured_by_a_returned_closure: agora #458 — a `sink ?String` parameter captured by a returned closure
// Closed: an option or a result that owns a String, a Vec or another handle, captured by a closure that leaves its function (returned as it is, or in a returned struct literal or closure), is copied into the closure's environment, which drops and copies it; the binding keeps its own (agora #458).
// main: heap-use-after-free (base 79e99d18).
// map: §7.5 | A2 | runs-clean | - | agora #458: a `sink ?String` parameter captured by a returned closure
$ `stdlib/core/string.nu`

@ cap sink ? String x → ( @ i ) {
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : ( @ i ) c ( cap @ ?String { T ( string_from `a caller value long enough for the heap` ) } )
    ( nurl_println_int ( c ) )
    ^ 0
}
