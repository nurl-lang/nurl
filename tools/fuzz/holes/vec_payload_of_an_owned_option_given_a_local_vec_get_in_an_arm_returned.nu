// vec_payload_of_an_owned_option_given_a_local_vec_get_in_an_arm_returned: agora #317 — (h6 of agora #1295) an owned `?Msg` given a local Vec's vec_get in one arm, its `( Vec i )` payload returned: taken on the path it owns, copied on the lent one, and the value it held before dropped.
// main: accepted; LeakSanitizer reported a leak (h6 also heap-use-after-free before #300).
// map: §7.6 | A2 | runs-clean | - | agora #317: (h6 of agora #1295) an owned `?Msg` given a local Vec's vec_get in one arm, its `( Vec i )` payload returned: taken on the path it owns, copied on the lent one, and the value it held before dropped (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: | Msg {
    MNone
    MSome ( Vec i )
}

@ make → ?Msg {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ^ @ ?Msg { T @ Msg { MSome xs } }
}

@ first i k → ( Vec i ) {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 7 )
    ( vec_push [Msg] ms @ Msg { MSome ys } )
    : ~ ? Msg om ( make )
    ? == k 1 { = om ( vec_get [Msg] ms 0 ) } {}
    ?? om { T m → { ?? m { MSome v → { ^ v } MNone → {} } } F → {} }
    ^ ( vec_new [i] )
}

@ main → i {
    : ( Vec i ) got ( first 1 )
    ( vec_push [i] got 42 )
    ( nurl_println_int ( vec_len [i] got ) )
    : ( Vec i ) got2 ( first 0 )
    ( nurl_println_int ( vec_len [i] got2 ) )
    ^ 0
}
