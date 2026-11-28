// map: §2.10 | A2 | rejected | - | AGORA-1041: a Slice of `( vec_at [( Vec s )] vv 0 )` whose element holds a view of String x, kept past x's growth: what the element holds stays a dependency on x itself
// AGORA-1041's guard: the fix reads the element's storage through vv's element, and what it holds (x) as it is, so growing x still ends the Slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    : ~ String x ( string_from `a string that lives on the heap for a while` )
    ( vec_push [s] ( vec_at [( Vec s )] vv 0 ) ( string_data x ) )
    : ( Slice s ) e1 ( slice_from_vec [s] ( vec_at [( Vec s )] vv 0 ) )
    ( string_push_str x `a long tail that grows the buffer several times over and over and over` )
    ( nurl_println ( slice_at [s] e1 0 ) )
    ^ 0
}
