// H452: `( mlkem_encaps_derand 768 ek m )` with a 4-byte `ek` (or a short
// `m`): K-PKE.Encrypt decoded the key's k polynomials and ρ at their
// fixed offsets, past the end of the Vec. `mlkem_encaps` passes its ek
// straight through.
// Closed: an ek that is not mlkem_ek_len bytes, or an m that is not 32,
// gives an empty ciphertext and shared secret (FIPS 203 §7.2).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/vec.nu`
$ `stdlib/std/mlkem.nu`

@ main → i {
    : ( Vec u ) ek ( vec_zeroed [u] 4 )
    : ( Vec u ) m ( vec_zeroed [u] 32 )
    : MlkemEncap e ( mlkem_encaps_derand 768 ek m )
    ( nurl_println_int ( vec_len [u] ( mlkem_ct e ) ) )
    ^ 0
}
