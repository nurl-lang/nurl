// H440: `( sha3_new 4000 6 )` built a sponge whose rate (4000 bytes) is
// past the 200-byte Keccak state; absorbing XORed the input into the
// state's lanes up to the rate, far past the 25-lane buffer. A rate of 0
// made the pad step write lane -1.
// Closed: sha3_new panics for a rate outside [1, 200].
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha3.nu`

@ main → i {
    : Sha3 h ( sha3_new 4000 6 )
    : ( Vec u ) d ( vec_zeroed [u] 3000 )
    ( sha3_absorb h d )
    ( nurl_println_int ( vec_len [u] ( sha3_squeeze h 8 ) ) )
    ^ 0
}
