// H467: a prepared MldsaKey's vectors are readable fields, and
// `vec_clear` + `vec_shrink_to_fit` on `. k a` released Â's storage in
// place; signing then read the matrix from the freed buffer.
// Closed: `mldsa_sign_mu_key` checks the key's vector sizes against its
// level once a signature (__mldsa_key_ok) and returns an empty Vec for a
// key that no longer matches.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/mldsa.nu`

@ main → i {
    : ( Vec u ) xi ( vec_zeroed [u] 32 )
    : MldsaKeys ks ( mldsa_keygen_derand 44 xi )
    : MldsaKey k ( mldsa_sign_key 44 ( mldsa_sk ks ) )
    ( vec_clear [i32] . k a ) ( vec_shrink_to_fit [i32] . k a )
    : ( Vec u ) mu ( vec_zeroed [u] 64 )
    : ( Vec u ) r ( vec_zeroed [u] 32 )
    : ( Vec u ) s ( mldsa_sign_mu_key k mu r )
    ( nurl_println_int ( vec_len [u] s ) )
    ^ 0
}
