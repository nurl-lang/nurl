// result_of_an_rc_share_given_back_or_cloned_by_a_callee_below_runs_clean: `= o ( f o k )` over a `!( Rc String ) String`, `f` below its caller handing back its argument on one run and an `rc_clone` share of its payload on another.
// Closed (agora #475): the keep rule took the new share for the old value because both name one block, and kept the old share instead of releasing it (one count leaked). It now keeps the old value only on a run the call lent its result: one it handed over is the caller's own value, whatever its key.
// map: §7.6 | A2 | runs-clean | - | agora #475: the keep rule for a result of an Rc share
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ~ ! ( Rc String ) String o @ !( Rc String ) String { T ( rc_new [String] ( string_from `the shared string, long enough for the heap` ) ) }
    = o ( f o 1 )
    = o ( f o 0 )
    = o ( f o 1 )
    ?? o { T r → { ( nurl_println ( string_data ( rc_get [String] r ) ) ) } F e → { ( nurl_println ( string_data e ) ) } }
    ^ 0
}

@ f ! ( Rc String ) String o i k → !( Rc String ) String {
    ? == k 1 { ^ o } {}
    ?? o { T r → { ^ @ !( Rc String ) String { T ( rc_clone [String] r ) } } F e → {} }
    ^ @ !( Rc String ) String { F ( string_from `a fresh error string, long enough for the heap` ) }
}
