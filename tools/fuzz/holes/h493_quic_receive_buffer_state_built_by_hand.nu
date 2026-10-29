// H493: a `QuicRxBufImpl` literal of the program's own with `base` 16
// and `consumed` 0 placed stream offset 0 sixteen bytes before its
// buffer, and `_quic_rxbuf_add_in` copied there.
// Closed: QuicRxBufImpl (and QuicRecoveryImpl) are sealed (`raw :`);
// quic_rxbuf_add's cap test no longer forms `off + len` before it.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/quic_rxbuf.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 256 )
    : ~ QuicRxBufImpl r @ QuicRxBufImpl { b 16 ( vec_new [i] ) 0 1000000 0 }
    : ( Vec u ) data ( vec_zeroed [u] 8 )
    : b ok ( _quic_rxbuf_add_in r 0 data )
    ( nurl_println_int ? ok 1 0 )
    ^ 0
}
