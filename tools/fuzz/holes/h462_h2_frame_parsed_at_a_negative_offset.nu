// H462: `( h2_parse_frame b -64 )` read the frame header and payload 64
// bytes before the buffer: the parser tested only that 9 bytes were left
// after `from` (`n - from < 9`), which a negative offset passes.
// Closed: a negative offset is H2FrameOther.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http2_frame.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    : !H2ParsedFrame H2FrameErr r ( h2_parse_frame b -64 )
    ?? r { T f → { ( nurl_println_int . f consumed ) } F e → { ( nurl_println ( h2_frame_err_name e ) ) } }
    ^ 0
}
