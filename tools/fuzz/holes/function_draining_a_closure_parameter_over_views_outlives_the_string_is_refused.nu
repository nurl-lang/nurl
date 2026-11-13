// function_draining_a_closure_parameter_over_views_outlives_the_string_is_refused: a user function that loops `( src 0 )` of its closure parameter into a ( Vec s ), handed `iter_from_vec` over a block's Vec of views
// Closed: agora #472, a closure parameter holds what its caller passes (`%src`), and what calling it hands back is tied to that argument.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #472: a function draining a closure parameter over views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/iter.nu`

@ collect_s ( @ ?s i ) src → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    : ~ b done F
    ~ ! done {
        : ?s got ( src 0 )
        ?? got {
            T x → { ( vec_push [s] out x ) }
            F → { = done T }
        }
    }
    ^ out
}

@ main → i {
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        = keep ( collect_s ( iter_from_vec [s] t ) )
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}
