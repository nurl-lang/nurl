// H472: `( h2_rx_consume rx -64 )` moved the buffer's tail down from 64
// bytes before its start: a count below the length was taken as a
// prefix to drop, a negative one too.
// Closed: a count <= 0 drops nothing.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http2_frame.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    ( h2_rx_consume b -64 )
    ( nurl_println_int ( vec_len [u] b ) )
    ^ 0
}
