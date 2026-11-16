// map: §2.10 | A2 | rejected | - | agora #838: `( pick c other )` with c bound from a builder call, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick ( @ v ) a ( @ v ) b → ( @ v ) { ^ a }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) other \ → v {}
    : ( @ v ) c0 ( mk xs )
    : ( @ v ) c ( pick c0 other )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
