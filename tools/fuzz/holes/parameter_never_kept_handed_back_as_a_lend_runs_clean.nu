// parameter_never_kept_handed_back_as_a_lend_runs_clean: agora #743 — `^ ( f0 p )` and `^ ( vec_at [String] p 0 )` over parameters the function never keeps: lends of the caller's own, still answered as lends (no per-call answer the callee never publishes)
// Control: the refusal asks whether the function takes the parameter over (a module-end fact); one it never keeps is the caller's, and a lend of it is handed back as before.
// main 3b63ee3b: accepted, runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #743: `^ ( f0 p )` and `^ ( vec_at [String] p 0 )` over parameters the function never keeps: lends of the caller's own, still answered as lends (no per-call answer the callee never publishes)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f0 String p → String { ^ p }

@ f1 String p → String { ^ ( f0 p ) }

@ fv ( Vec String ) p → String { ^ ( vec_at [String] p 0 ) }

@ main → i {
    : ~ String x ( string_from `a string long enough to live on the heap for sure` )
    : String s ( f1 x )
    ( nurl_println ( string_data s ) )
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element long enough to live on the heap too` ) )
    : String e ( fv v )
    ( nurl_println ( string_data e ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}
