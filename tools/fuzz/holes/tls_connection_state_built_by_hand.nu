// tls_connection_state_built_by_hand: a `TlsConnImpl` literal of the program's own — a connection
// state with empty keys and buffers — went to the record layer's
// `_tls_rec_range_to c out 0 23 data 0 4096`, which sealed 4096 bytes of
// a one-byte buffer. The *Impl state is the record layer's to build.
// Closed: TlsConnImpl (and CliHsImpl, SrvHsImpl) are sealed (`raw :`),
// so a literal of one or a write to its fields needs `unsafe`;
// _tls_rec_range_to also checks [lo, hi) against `data`.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | rejected | h487 | a `TlsConnImpl` literal of the program's own — a connection state with empty keys and buffers — went to the record layer's `_tls_rec_range_to c out 0 23 data 0 4096`, which sealed 4096 bytes of a…
$ `stdlib/core/vec.nu`
$ `stdlib/std/tls.nu`

@ main → i {
    : ~ TlsConnImpl c @ TlsConnImpl { 0 0 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( aes_gcm_key_new ( vec_new [u] ) ) ( aes_gcm_key_new ( vec_new [u] ) ) ( vec_new [u] ) 1 0 0 0 ( vec_new [u] ) ( vec_new [u] ) 0 0 0 0 0 0 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) 0 0 13 ( vec_new [u] ) ( vec_new [u] ) 0 ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) 0 0 0 0 }
    : ( Vec u ) data ( vec_new [u] )
    ( vec_push [u] data # u 1 )
    : ( Vec u ) out ( vec_new [u] )
    ( _tls_rec_range_to c out 0 23 data 0 4096 )
    ( nurl_println_int ( vec_len [u] out ) )
    ^ 0
}
