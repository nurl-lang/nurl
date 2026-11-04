// foreach_over_nothing_leaves_an_inout_vec_param_holding_its_views: a foreach over an empty Vec gives an inout ( Vec s ) parameter a new Vec.
// Closed: a parameter the body may give a new value (`inout`, or one it owns) holds what it held on entry only on the paths that do not: its pseudo `%p` is a dependency the joins and a loop's dependency snapshot follow.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | Family G review: a foreach over an empty Vec gives an inout ( Vec s ) parameter a new Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f inout ( Vec s ) d ( Vec i ) xs → ( Vec s ) {
    ~ x xs { = d ( vec_new [s] ) }
    ^ ( vec_clone [s] d )
}

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ~ ( Vec s ) t ( vec_new [s] )
    : ( Vec i ) none ( vec_new [i] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        ( vec_push [s] t ( string_data b ) )
        = ws ( f t none )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
