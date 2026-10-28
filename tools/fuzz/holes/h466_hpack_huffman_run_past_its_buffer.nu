// H466: `( _hpack_huffman_decode b 0 4000 )` decoded 4000 bytes out of a
// 16-byte buffer: the range was trusted, since both callers check it,
// but the helper carries one underscore and any program could call it.
// Closed: a range outside the buffer is HpackTruncated (one check per
// call, outside the decode loop).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http2_hpack.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    : !String HpackErr r ( _hpack_huffman_decode b 0 4000 )
    ?? r { T s → { ( nurl_println_int ( string_len s ) ) } F e → { ( nurl_println ( hpack_err_name e ) ) } }
    ^ 0
}
