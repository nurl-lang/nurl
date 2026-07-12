// Arm-local staleness. The stale-borrow diagnostic (§2.10) must not fire on
// code where the mutation and the use are on MUTUALLY EXCLUSIVE paths — the
// no-false-positive contract. Both shapes below appear in the stdlib
// (ext/http_static.nu, ext/websocket.nu) and used to be flagged.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ pick b take ( Vec u ) v → i {
    : *u p ( vec_data [u] v )
    // 1. sibling arms: the free is on the other path from the use
    ? take {
        ( vec_clear [u] v )  // this path drops the buffer …
        ^ -1
    } {
        ^ # i . p 0  // … and this one never runs it
    }
}

@ early ( Vec u ) v → i {
    : *u p ( vec_data [u] v )
    // 2. the freeing arm RETURNS, so its mutation cannot reach the code
    //    after the `?` — the classic guard-clause shape
    ? == 0 ( vec_len [u] v ) {
        ( vec_free [u] v )
        ^ -1
    } {}
    ^ # i . p 0
}

@ main → i {
    : ( Vec u ) a ( vec_with_cap [u] 4 )
    ( vec_push [u] a # u 7 )
    ( nurl_print ( nurl_str_int ( pick F a ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( early a ) ) ) ( nurl_print `\n` )
    ( vec_free [u] a )
    ^ 0
}
