// callee_growing_an_element_of_an_argument_beside_a_view_of_another_vec_runs_clean: AGORA-923 guard — `( g vv s )`, s a slice of an unrelated src, read after the call too: accepted (github#2041's direct-call form)
// map: §2.10 | A2 | runs-clean | - | AGORA-923 guard: a callee growing an element of an argument beside a view of an unrelated Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ g ( Vec ( Vec i ) ) vv ( Slice i ) s → v {
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] ( vec_at [( Vec i )] vv 0 ) k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] s 0 ) )
}

@ main → i {
    : ( Vec ( Vec i ) ) vv ( vec_new [( Vec i )] )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 7 )
    ( vec_push [( Vec i )] vv a )
    : ( Vec i ) src ( vec_new [i] )
    ( vec_push [i] src 9 )
    : ( Slice i ) s ( slice_from_vec [i] src )
    ( g vv s )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}
