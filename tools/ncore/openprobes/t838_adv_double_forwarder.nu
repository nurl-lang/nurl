// map: §2.10 | A2 | rejected | - | adversarial: two forwarders, then the closure run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ idc ( @ v ) f → ( @ v ) { ^ f }

@ fw ( @ v ) f → ( @ v ) { ^ ( idc f ) }

@ fw2 ( @ v ) f → ( @ v ) { ^ ( fw f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( fw2 ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
