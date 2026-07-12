// A pointer borrowed from a container (vec_data/string_data/bytes_data)
// dangles once the container is grown — the buffer may be reallocated
// under it. The mutation here is inside a loop body, the use after it.
// Re-fetching the pointer clears the diagnostic (the second read below
// is silent), which is exactly the fix the note suggests.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

@ main → i {
    : ( Vec u ) v ( vec_with_cap [u] 4 )
    ( vec_push [u] v # u 7 )
    : ~ * u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k 100 {
        ( vec_push [u] v # u 1 )  // grows → realloc → p dangles
        = k + k 1
    }
    : i stale # i . p 0  // warns: 'p' is stale
    = p ( vec_data [u] v )  // re-fetch
    : i fresh # i . p 0  // silent
    ( nurl_print ( nurl_str_int + - stale stale fresh ) ) ( nurl_print `\n` )
    ( vec_free [u] v )

    // Same hazard through a byte buffer (a `Vec u8`, so the borrow is
    // `vec_data` too). `bytes_push_int` is one of
    // the six growers the compiler's hand-written mutator list originally
    // missed — the prefix rule (`bytes_push_*`) catches it.
    : ( Vec u ) b ( vec_with_cap [u] 4 )
    ( bytes_push_u16_le b 1 )
    : ~ * u bp ( vec_data [u] b )
    ( bytes_push_int b 2 )  // may realloc → bp dangles
    : i sb # i . bp 0  // warns: 'bp' is stale
    ( nurl_print ( nurl_str_int - sb sb ) ) ( nurl_print `\n` )
    ( vec_free [u] b )

    // Join: the mutation is in a `?`-arm that FALLS THROUGH, so after the
    // conditional the pointer may or may not have been invalidated — stale
    // on either path is stale here.
    : ( Vec u ) c ( vec_with_cap [u] 4 )
    ( vec_push [u] c # u 3 )
    : *u cp ( vec_data [u] c )
    ? > ( vec_len [u] c ) 0 { ( vec_push [u] c # u 4 ) } {}
    ( nurl_print ( nurl_str_int # i . cp 0 ) ) ( nurl_print `\n` )  // warns
    ( vec_free [u] c )
    ^ 0
}
