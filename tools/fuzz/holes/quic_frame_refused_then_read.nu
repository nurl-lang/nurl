// quic_frame_refused_then_read: `quic_frame_parse` refuses a malformed frame with the null
// QuicFrame, and `quic_frame_type` of it read address 0.
// Closed: `quic_frame_ok` tells the null frame; an accessor of it panics
// instead of reading through it.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | runs-clean | h495 | `quic_frame_parse` refuses a malformed frame with the null QuicFrame, and `quic_frame_type` of it read address 0.
$ `stdlib/core/vec.nu`
$ `stdlib/std/quic_frame.nu`

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 255 )
    : QuicFrame f ( quic_frame_parse b 0 )
    ( nurl_println_int ( quic_frame_type f ) )
    ^ 0
}
