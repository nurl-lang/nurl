// H465: `( hpack_decode_string b -64 )` read the Huffman flag byte 64
// bytes before the buffer before it decoded the length: like
// hpack_decode_int it tested only `from >= n`.
// Closed: a negative offset is HpackOther.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http2_hpack.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    : !HpackString HpackErr r ( hpack_decode_string b -64 )
    ?? r { T v → { ( nurl_println_int . v consumed ) } F e → { ( nurl_println ( hpack_err_name e ) ) } }
    ^ 0
}
