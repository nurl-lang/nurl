// x25519_point_shorter_than_32_bytes: `( x25519 k p )` with a one-byte point: the ladder read 32 bytes
// through `vec_data` with no length check, past the end of the point's
// buffer. A TLS 1.2 server reached it from the wire — its
// ServerKeyExchange names the key's length, and the client handed a key
// of any length to x25519 (found by the `tlscli` parser fuzzer).
// Closed: an x25519 input that is not 32 bytes gives 32 zero bytes, the
// output RFC 7748 §6.1 tells every caller to refuse; the TLS 1.2 client
// refuses a key of the wrong size for its curve and an all-zero secret.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h435 | `( x25519 k p )` with a one-byte point: the ladder read 32 bytes through `vec_data` with no length check, past the end of the point's buffer. A TLS 1.2 server reached it from the wire — its…
$ `stdlib/core/vec.nu`
$ `stdlib/std/x25519.nu`

@ main → i {
    : ( Vec u ) k ( vec_new [u] )
    ~ < ( vec_len [u] k ) 32 { ( vec_push [u] k # u 7 ) }
    : ( Vec u ) p ( vec_new [u] )
    ( vec_push [u] p # u 9 )
    : ( Vec u ) r ( x25519 k p )
    ( nurl_println ( nurl_str_int ( vec_len [u] r ) ) )
    ^ 0
}
