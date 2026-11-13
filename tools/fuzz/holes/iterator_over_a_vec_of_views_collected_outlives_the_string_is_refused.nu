// iterator_over_a_vec_of_views_collected_outlives_the_string_is_refused: `iter_collect` of `iter_from_vec` over a block's ( Vec s ) of views of a block's String, kept in a Vec read after the block
// Closed: agora #472, a trusted callee's closure argument is held as its other arguments are: what calling it hands back may be a copy of what it holds.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #472: iter_collect of an iterator over a Vec of views outliving the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_collect [s] ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
