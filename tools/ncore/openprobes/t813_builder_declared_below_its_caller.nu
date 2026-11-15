// map: §2.10 | A2 | rejected | - | agora #813: a returned closure growing its captured argument, its builder declared below the caller, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`


@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }
