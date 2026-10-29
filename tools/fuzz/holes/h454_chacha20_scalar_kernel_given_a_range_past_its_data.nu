// H454: `_chacha20_xor_range_scalar`, the big-endian reference kernel,
// carries one underscore, so any program could call it, and it reads
// data[doff, doff + n) through `vec_data` unchecked: 4096 bytes from an
// 8-byte Vec.
// Closed: the kernel is `raw` (it requires the range inside `data`,
// which chacha20_xor_range checks); only an `unsafe` caller may call it.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ main → i {
    : ( Vec u ) k ( vec_zeroed [u] 32 )
    : ( Vec u ) n ( vec_zeroed [u] 12 )
    : ( Vec u ) d ( vec_zeroed [u] 8 )
    : ( Vec u ) o ( _chacha20_xor_range_scalar k 0 n d 0 4096 )
    ( nurl_println_int ( vec_len [u] o ) )
    ^ 0
}
