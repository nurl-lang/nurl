// map: §2.10 | A2 | rejected | - | agora #838: a builder's closure assigned in an arm, captured by a literal and run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ~ ( @ v ) d \ → v {}
    ? > ( vec_len [u] xs ) 0 { = d c } {}
    : ( @ v ) e \ → v { ( d ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( e )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

