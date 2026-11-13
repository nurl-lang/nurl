// iterator_over_a_vec_of_views_called_directly_outlives_the_string_is_refused: `( it 0 )` of `iter_from_vec` over a block's ( Vec s ) of views, kept in an option read after the block
// Closed: agora #472, a closure value's call holds what the closure holds (`\~v(it)`).
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #472: a direct call of an iterator over views outliving the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ? s keep @ ?s { F }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        : ( @ ?s i ) it ( iter_from_vec [s] t )
        = keep ( it 0 )
    }
    ?? keep { T x → { ( nurl_println x ) } F → {} }
    ^ 0
}
