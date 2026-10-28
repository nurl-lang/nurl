// H462: `hpack_decode_int` tested only `from >= n`, so a negative offset
// read before the buffer; QPACK's decoder-stream reader
// (`qpack_decoder_instruction buf off`) handed its offset straight to it.
// Closed: hpack_decode_int (and hpack_decode_string) refuse a negative
// offset (HpackOther); the QPACK instruction readers answer -2 for one.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http3_qpack.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    ( nurl_println_int ( qpack_decoder_instruction b -64 ) )
    : !HpackInt HpackErr r ( hpack_decode_int b -64 7 )
    ?? r { T v → { ( nurl_println_int . v value ) } F e → { ( nurl_println ( hpack_err_name e ) ) } }
    ^ 0
}
