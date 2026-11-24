// in_param_named_twice_in_a_returned_literal_given_a_local_runs_clean: `^ ( dup x )`, `dup` returning `@ K2 { p p }`, x a local of the caller
// A parameter a returned literal names twice is lent in part (nurlc's twicelit, AGORA-995): no return handover of a local handed to it, so `x` is copied into the result and released, not handed over into two fields. The reference checker counts the names too (its `twice` summary record; review of github#2280).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a parameter named twice in a returned literal is no whole lend
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ dup String p → K2 { ^ @ K2 { p p } }

@ esc → K2 {
    : String x ( string_from `a local value long enough for the heap` )
    ^ ( dup x )
}

@ main → i {
    : K2 k ( esc )
    ( nurl_println ( string_data . k a ) )
    ( nurl_println ( string_data . k b ) )
    ^ 0
}
