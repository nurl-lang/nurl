// H766: agora #183 — an option `?` assigned to an `inout ?String` (option_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout ? String o b c → v {
    : String x ( mk )
    = o ? c @ ?String { T x } @ ?String { F }
}

@ main → i {
    : ~ ? String o @ ?String { T ( mk ) }
    ( fill o T )
    ( nurl_println_int ?? o { T s → ( string_len s ) F → 0 } )
    ^ 0
}
