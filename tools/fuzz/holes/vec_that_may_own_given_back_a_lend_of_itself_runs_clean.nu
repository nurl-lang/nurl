// vec_that_may_own_given_back_a_lend_of_itself_runs_clean: `: ~ v ? > c 0 ( vec_new … ) h` owns its value on one path only; `: x { v }` then `= v x` gives it back, and a `: ~ w v` cursor handed back the same way (`= v w`).
// Closed (agora #667): on the path v owned its value, `= v x` released it and stored the same buffer back (heap-use-after-free). x, bound as a lend, is now asked by its key.
// map: §7.6 | A2 | runs-clean | - | agora #667: a binding that may own its value given back a lend of itself
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ g i c ( Vec String ) h → i {
    : ~ ( Vec String ) v ? > c 0 ( vec_new [String] ) h
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : __e2 { v }
    = v __e2
    ^ # i ( vec_len [String] v )
}

@ g2 i c ( Vec String ) h → i {
    : ~ ( Vec String ) v ? > c 0 ( vec_new [String] ) h
    : ~ ( Vec String ) w v
    = v w
    ^ # i ( vec_len [String] v )
}

@ main → i {
    : ( Vec String ) h ( vec_new [String] )
    ( nurl_println_int ( g 1 h ) )
    ( nurl_println_int ( g2 1 h ) )
    ^ 0
}
