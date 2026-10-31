// sha3x4_sponge_rate_past_the_keccak_state: `( sha3x4_new 4000 31 )`, the four-way sponge, took any rate as
// sha3_new did: absorbing 3000 bytes per way wrote past the 100-lane
// state.
// Closed: sha3x4_new panics for a rate outside [1, 200].
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h452 | `( sha3x4_new 4000 31 )`, the four-way sponge, took any rate as sha3_new did: absorbing 3000 bytes per way wrote past the 100-lane state.
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha3x4.nu`

@ main → i {
    : Sha3x4 h ( sha3x4_new 4000 31 )
    : ( Vec u ) d ( vec_zeroed [u] 3000 )
    ( sha3x4_absorb h d d d d )
    ^ 0
}
