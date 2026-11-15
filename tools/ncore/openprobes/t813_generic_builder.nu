// map: §2.10 | A2 | rejected | - | agora #813: a returned closure growing its captured argument, its builder generic, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk [T] ( Vec T ) x → ( @ v ) { ^ \ → v { ( vec_reserve [T] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk [u] xs )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

