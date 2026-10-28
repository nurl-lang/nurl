// H473: `( _tls_word_release 4096 )` released the TLS connection "owned"
// by the word 4096: the helper wraps shared_from_word, which only an
// `unsafe` function may call, under one underscore. `_tls_word` (an
// owner that is never given back) and `_tls_conn_new raw` (a connection
// that closes any socket handle) had the same gap.
// Closed: the three are `raw`, so only an `unsafe` caller may call them.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/std/tls.nu`

@ main → i {
    ( _tls_word_release 4096 )
    ^ 0
}
