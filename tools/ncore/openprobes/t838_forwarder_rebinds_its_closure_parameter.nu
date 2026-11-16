// map: §2.10 | A2 | rejected | - | agora #838: a forwarder `: g f ^ g` handed a builder's closure, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ fw ( @ v ) f → ( @ v ) { : ( @ v ) g f ^ g }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( fw ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
