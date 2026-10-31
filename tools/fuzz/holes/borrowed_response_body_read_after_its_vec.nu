// borrowed_response_body_read_after_its_vec: `( response_set_body_borrowed_bytes r b )` made the response's
// body a view of `b` with nothing tying the two: `b` died with the helper
// that made it, and serializing the response read the freed buffer.
// Closed: the zero-copy body is `raw` — its contract (the Vec outlives
// the write) is the caller's, so only an `unsafe` caller may make it;
// `response_set_body_bytes` copies.
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §3.3d | B | rejected | h477 | `( response_set_body_borrowed_bytes r b )` made the response's body a view of `b` with nothing tying the two: `b` died with the helper that made it, and serializing the response read the freed buffer.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http_response.nu`

@ attach HttpResponse r → v {
    : ( Vec u ) b ( vec_new [u] )
    ~ < ( vec_len [u] b ) 200 { ( vec_push [u] b # u 65 ) }
    ( response_set_body_borrowed_bytes r b )
}

@ main → i {
    : HttpResponse r ( response_new 200 )
    ( attach r )
    : ( Vec u ) w ( response_serialize r )
    ( nurl_println_int ( vec_len [u] w ) )
    ^ 0
}
