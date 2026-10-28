// H440: `( chacha20poly1305_open_in key iv seq buf aad_at data_at end )`
// with `data_at` near 2^63: the check `data_at + 16 > end` wrapped and
// passed, and the record was MACed and zeroed from 2^63 bytes past the
// buffer. (`chacha20poly1305_seal_in` checks its offsets without
// arithmetic and was not affected.)
// Closed: the check is `end < 16 | end > len | data_at > end - 16`, which
// cannot wrap; the call returns F.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ main → i {
    : ( Vec u ) k ( vec_zeroed [u] 32 )
    : ( Vec u ) iv ( vec_zeroed [u] 12 )
    : ( Vec u ) buf ( vec_zeroed [u] 64 )
    : b r ( chacha20poly1305_open_in k iv 0 buf 0 9223372036854775800 64 )
    ( nurl_println ? r `opened` `refused` )
    ^ 0
}
