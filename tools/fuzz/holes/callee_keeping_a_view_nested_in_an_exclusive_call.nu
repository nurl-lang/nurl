// callee_keeping_a_view_nested_in_an_exclusive_call: agora #558 — `( k ( keep hv s ) hv s )`: keep pushes string_data s into an inout Vec of views, k grows s and reads hv
// Refused on main and with #558, which keeps a nested call's own rows ahead of the enclosing call's checks.
// map: §2.10 | A2 | rejected | - | agora #558: `( k ( keep hv s ) hv s )`: keep pushes string_data s into an inout Vec of views, k grows s and reads hv
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ keep inout ( Vec s ) hv inout String s → i { ( vec_push [s] hv ( string_data s ) ) ^ 0 }

@ k i z inout ( Vec s ) hv inout String s → v {
    ( string_push_str s `and a long tail that makes the buffer move, more than the first capacity holds` )
    ( nurl_println ( vec_at [s] hv 0 ) )
}

@ main → i {
    : ~ ( Vec s ) hv ( vec_new [s] )
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    ( k ( keep hv s ) hv s )
    ^ 0
}
