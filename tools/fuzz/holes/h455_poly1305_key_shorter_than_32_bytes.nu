// H455: `( poly1305_mac otk msg )` with an empty one-time key: the MAC
// read r and s as 32 bytes through `vec_data` whatever the key's length.
// Closed: a key that is not 32 bytes gives an empty tag.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

@ main → i {
    : ( Vec u ) k ( vec_new [u] )
    : ( Vec u ) m ( vec_zeroed [u] 16 )
    : ( Vec u ) t ( poly1305_mac k m )
    ( nurl_println_int ( vec_len [u] t ) )
    ^ 0
}
