// map: §2.10 | A2 | rejected | - | agora #428: a slice taken through a `: ~` copy of a Vec kept while the owner itself is pushed
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 1 )
    ( vec_push [i] vs 2 )
    : ~ ( Vec i ) w vs
    : ( Slice i ) sl ( slice_from_vec [i] w )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] vs k ) = k + k 1 }
    ?? ( slice_get [i] sl 1 ) { T x → ( nurl_print_int x ) F → {} }
    ^ 0
}
