// map: §2.10 | A2 | rejected | - | agora #838: a closure literal's call hands back a builder's closure it captured, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( @ ( @ v ) ) g \ → ( @ v ) { ^ c }
    : ( @ v ) d ( g )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
