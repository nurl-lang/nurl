// filtered_iterator_over_a_vec_of_views_collected_outlives_the_string_is_refused: `iter_collect` of `iter_filter` over `iter_from_vec` of a block's Vec of views
// Closed: agora #472, as iter_map.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #472: a filtered iterator over views collected
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_collect [s] ( iter_filter [s] ( iter_from_vec [s] t ) \ s x → b { ^ T } ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
