// binding_repointed_in_arms_returned_beside_lent_and_fresh_returns: agora #300 — (h2) a `: ~ String` re-pointed in the arms at a local Vec's element or a parameter's, returned, in a function whose other returns lend a parameter's element or hand over a fresh value.
// main: accepted; LeakSanitizer reported a leak (heap-use-after-free on 29860991).
// map: §7.6 | A2 | runs-clean | - | agora #300: (h2) a `: ~ String` re-pointed in the arms at a local Vec's element or a parameter's, returned, in a function whose other returns lend a parameter's element or hand over a fresh value (leak / UAF)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick ( Vec String ) ps i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    ? == k 2 { ^ ( vec_at [String] ps 0 ) } {}
    ? == k 3 { ^ ( string_from `a fresh string long enough for the heap` ) } {}
    : ~ String e ( string_from `fresh string long enough to be on the heap` )
    ? == k 1 { = e ( vec_at [String] vs 0 ) } { = e ( vec_at [String] ps 0 ) }
    ^ e
}

@ main → i {
    : ( Vec String ) qs ( vec_new [String] )
    ( vec_push [String] qs ( string_from `a parameter string long enough for the heap` ) )
    : String s ( pick qs 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
