// join_of_call_bound_closures_handed_to_a_runner_beside_a_view_is_refused: a `?` join of two closures bound from a maker's calls, one growing the Vec it was handed, handed to a runner; a slice of the Vec is read after (claude-finish's hp03, #817's review)
// Closed: agora #838, a closure argument that is a join is asked by the closures it may be.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a join of call-bound closures handed to a runner grows a Vec beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec u ) ys ( vec_new [u] )
    : ( @ v ) c1 ( mk xs )
    : ( @ v ) c2 ( mk ys )
    : b k > ( vec_len [u] xs ) 0
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( run ? k c1 c2 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
