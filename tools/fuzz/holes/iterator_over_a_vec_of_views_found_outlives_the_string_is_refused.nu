// iterator_over_a_vec_of_views_found_outlives_the_string_is_refused: `iter_find` over `iter_from_vec` of a block's Vec of views, kept in an option read after the block
// Closed: agora #472, as iter_collect: the found element is a copy of what the iterator holds.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #472: iter_find of an iterator over views outliving the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ main → i {
    : ~ ? s keep @ ?s { F }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( iter_find [s] ( iter_from_vec [s] t ) \ s x → b { ^ T } )
    }
    ?? keep { T x → { ( nurl_println x ) } F → {} }
    ^ 0
}
