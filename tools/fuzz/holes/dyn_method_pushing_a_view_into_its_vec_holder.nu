// dyn_method_pushing_a_view_into_its_vec_holder: an impl pushing a view of its String argument into its Vec argument.
// Closed: a `dyn` method's virtual callee answers the holder/source question (g_fn_vkeeps) with the union of its impls' answers, and a parked caller is walked after the impls it may run (agora #394).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #394: an impl pushing a view of its String argument into its Vec argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Put [T] {
    @ put T self ( Vec s ) h String s → v
}

: Lens { i k }

% Put Lens { @ put Lens l ( Vec s ) h String s → v { ( vec_push [s] h ( string_data s ) ) } }

@ main → i {
    : Lens l @ Lens { 1 }
    : %Put d ( dyn Put l )
    : ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `the first heap string, long enough to be on the heap for sure` )
        ( put d hold s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
