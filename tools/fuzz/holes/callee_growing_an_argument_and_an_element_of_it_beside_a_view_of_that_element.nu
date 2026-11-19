// callee_growing_an_argument_and_an_element_of_it_beside_a_view_of_that_element: AGORA-923 — `( g vv s )`, s a slice of `( vec_at vv 0 )`, g pushes through `( vec_at vv 0 )` of its borrowed vv, then pushes to vv itself, then reads s (github#2076's review)
// AGORA-923 (closed): refused (main dfcf10c6: accepted, heap-use-after-free); the (B') counterexample of agora #3964
// map: §2.10 | A2 | rejected | - | AGORA-923: a view of an argument's element handed beside it to a callee that grows that element and the argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g ( Vec ( Vec i ) ) vv ( Slice i ) s → v {
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) k ) = k + k 1 }
    ( vec_push [( Vec i )] vv ( vec_new [i] ) )
    ( nurl_println_int ( slice_at [i] s 0 ) )
}

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 7 )
    ( vec_push [( Vec i )] vv a )
    : ( Slice i ) s ( slice_from_vec [i] ( vec_at [( Vec i )] vv 0 ) )
    ( g vv s )
    ^ 0
}
