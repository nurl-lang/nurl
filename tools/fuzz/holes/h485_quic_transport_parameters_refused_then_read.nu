// H485: `quic_tp_decode` refuses an invalid encoding with the null
// QuicTp, which safe code could not tell from a good one, and every
// accessor read through it: the setter after a refused decode wrote to
// address 0.
// Closed: `quic_tp_ok` tells the null QuicTp; an accessor of it panics
// (one test where every accessor fetches the state) instead of reading
// through it.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/quic_tp.nu`

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 255 )
    : QuicTp t ( quic_tp_decode b F )
    ( quic_tp_set_max_idle_timeout t 5 )
    ( nurl_println_int ( quic_tp_max_idle_timeout t ) )
    ^ 0
}
