// map: §2.10 | A2 | rejected | - | agora #838: a builder call handed through an identity inside a loop, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ idc ( @ v ) f → ( @ v ) { ^ f }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ~ ( @ v ) c \ → v {}
    : ~ i k 0
    ~ < k 2 { = c ( idc ( mk xs ) ) = k + k 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

