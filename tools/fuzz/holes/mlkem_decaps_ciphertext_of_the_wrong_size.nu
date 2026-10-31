// mlkem_decaps_ciphertext_of_the_wrong_size: `( mlkem_decaps 768 dk ct )` with a 4-byte ciphertext (or a short
// dk): K-PKE.Decrypt decoded u and v at their fixed offsets, past the end
// of the Vec.
// Closed: a dk or ct that is not the level's size gives an empty Vec
// (FIPS 203 §7.3's input check).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | runs-clean | h464 | `( mlkem_decaps 768 dk ct )` with a 4-byte ciphertext (or a short dk): K-PKE.Decrypt decoded u and v at their fixed offsets, past the end of the Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/std/mlkem.nu`

@ main → i {
    : ( Vec u ) d ( vec_zeroed [u] 32 )
    : ( Vec u ) z ( vec_zeroed [u] 32 )
    : MlkemKeys k ( mlkem_keygen_derand 768 d z )
    : ( Vec u ) ct ( vec_zeroed [u] 4 )
    : ( Vec u ) ss ( mlkem_decaps 768 ( mlkem_dk k ) ct )
    ( nurl_println_int ( vec_len [u] ss ) )
    ^ 0
}
