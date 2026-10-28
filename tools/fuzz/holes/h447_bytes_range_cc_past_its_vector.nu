// H447: `( bytes_range_cc v lo hi )`, chacha20poly1305.nu's copy helper,
// copied v[lo, hi) with no check of either bound: 4096 bytes out of an
// 8-byte Vec.
// Closed: the helper is `raw` (0 ≤ lo ≤ hi ≤ len, which its seal/open
// callers check); only an `unsafe` caller may call it.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ main → i {
    : ( Vec u ) v ( vec_zeroed [u] 8 )
    : ( Vec u ) o ( bytes_range_cc v 0 4096 )
    ( nurl_println_int ( vec_len [u] o ) )
    ^ 0
}
