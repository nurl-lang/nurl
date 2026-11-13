// option_handed_over_by_name_given_a_new_value_survives_a_panic_runs_clean: an option handed over by name, given a new value, then a panic under recover; and one that may own its value (`? == c 1 @ ?String { T … } h0`), handed over and not read again.
// Control for agora #667: the handover is a move for an option too, and the walk says so. Nothing is refused where the moved source is not read before it has a new value, and both run clean.
// map: §7 | A2 | runs-clean | - | agora #667: an option handed over by name, under a panic and out of one that may own its value
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ work i n → i {
    : ~ ? String a @ ?String { T ( string_from `option A, long enough for the heap allocation` ) }
    : ~ ? String t @ ?String { T ( string_from `option T, long enough for the heap allocation` ) }
    = t a
    = a @ ?String { T ( string_from `option N, long enough for the heap allocation` ) }
    ? == n 1 { ( panic `after the handover` ) } {}
    : ~ i k 0
    ?? a { T s → { = k + k ( string_len s ) } F → {} }
    ?? t { T s → { = k + k ( string_len s ) } F → {} }
    ^ k
}

@ pick i c ? String h0 → i {
    : ~ ? String a ? == c 1 @ ?String { T ( string_from `an owned option string, long enough for the heap` ) } h0
    : ~ ? String t @ ?String { T ( string_from `the t option string, long enough for the heap yes` ) }
    = t a
    ?? t { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    = t @ ?String { T ( string_from `a new t option string, long enough for the heap` ) }
    ^ 0
}

@ run ( @ v ) f → v { : !v PanicInfo r ( recover f ) }

@ main → i {
    ( run \ → v { : i r ( work 1 ) } )
    ( nurl_println_int ( work 0 ) )
    : ?String h @ ?String { T ( string_from `the lender option string, long enough heap` ) }
    ( pick 1 h ) ( pick 0 h )
    ^ 0
}
