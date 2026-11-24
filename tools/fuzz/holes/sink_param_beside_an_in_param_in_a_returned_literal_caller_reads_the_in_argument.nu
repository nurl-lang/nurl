// sink_param_beside_an_in_param_in_a_returned_literal_caller_reads_the_in_argument: `f` returns `@ K2 { p q }` with `q` a declared `sink`, and the caller reads its `p` argument after the call
// Guard: a sink named whole makes the literal own its fields, so `p` is taken over too and the read is of a moved value (AGORA-995, review of github#2280).
// main: rejected.
// map: CallT.sink | A1 | rejected | - | AGORA-995: a literal beside a sink parameter takes the in parameter over
$ `stdlib/core/string.nu`

: K2 { String a String b }

@ f String p sink String q → K2 { ^ @ K2 { p q } }

@ main → i {
    : String y ( string_from `the caller's value, long enough for the heap` )
    : K2 k ( f y ( string_from `a sunk value long enough for the heap buffer` ) )
    ( nurl_println ( string_data . k a ) )
    ( nurl_println ( string_data y ) )
    ^ 0
}
