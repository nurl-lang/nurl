// map: §2.10 | A2 | rejected | - | agora #813: a local growing literal handed through `pick` returning its argument, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ pick ( @ v ) f → ( @ v ) { ^ f }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( pick \ → v { ( vec_reserve [u] xs 4096 ) } )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
