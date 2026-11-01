// vec_payload_of_an_option_owned_on_some_paths_lent_by_a_local_vec_returned: agora #300 — (h6) the same with a `( Vec i )` payload: taken on the path the option owns, lent by the local Vec on the other.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (h6) the same with a `( Vec i )` payload: taken on the path the option owns, lent by the local Vec on the other (UAF)
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
    : ~ ? Msg om ( vec_get [Msg] ms 0 )
    ? == k 0 { = om ( make ) } {}
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
