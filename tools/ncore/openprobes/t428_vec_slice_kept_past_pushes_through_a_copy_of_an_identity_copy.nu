// map: §2.10 | A2 | rejected | - | agora #428: a slice of a Vec kept while `: ( Vec i ) w ( id vs )  : ~ ( Vec i ) w2 w` pushes through w2
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ id ( Vec i ) v → ( Vec i ) { ^ v }

@ main → i {
    : ( Vec i ) vs ( vec_new [i] )
    ( vec_push [i] vs 1 )
    ( vec_push [i] vs 2 )
    : ( Slice i ) sl ( slice_from_vec [i] vs )
    : ( Vec i ) w ( id vs )
    : ~ ( Vec i ) w2 w
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] w2 k ) = k + k 1 }
    ?? ( slice_get [i] sl 1 ) { T x → ( nurl_print_int x ) F → {} }
    ^ 0
}
