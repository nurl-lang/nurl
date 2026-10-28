// H442: `( chacha20_xor_range key ctr nonce data doff n )` with `n` past
// the end of `data`: the documented entry point left the range to its
// caller, and the keystream XOR read 4096 bytes from an 8-byte Vec.
// Closed: a range not inside `data` (negative `doff` or `n`, or `n`
// past `len - doff`) gives an empty Vec — one check a call.
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ main → i {
    : ( Vec u ) k ( vec_zeroed [u] 32 )
    : ( Vec u ) n ( vec_zeroed [u] 12 )
    : ( Vec u ) d ( vec_zeroed [u] 8 )
    : ( Vec u ) o ( chacha20_xor_range k 0 n d 0 4096 )
    ( nurl_println_int ( vec_len [u] o ) )
    ^ 0
}
