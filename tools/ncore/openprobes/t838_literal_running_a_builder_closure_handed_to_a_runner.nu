// map: §2.10 | A2 | rejected | - | agora #838: `( run \ → v { ( c ) } )` with c from a builder call, beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( run \ → v { ( c ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
