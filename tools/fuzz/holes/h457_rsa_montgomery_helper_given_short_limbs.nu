// H457: rsa_mont.nu's Montgomery helpers (`_rm_mul_d`, `_rm_sqr_d`,
// `_rm_enter`, `_rm_leave`, `_rm_pow_ct`, `_rm_pow_pub`, `_rm_pow2_ct`)
// carry one underscore, so any program could call them, and each trusts
// its residues to hold the context's n limbs: an empty destination and
// operands were read and written as 16 limbs.
// Closed: the helpers are `raw`; only an `unsafe` caller, vouching for
// the limb counts, may call them.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/rsa_mont.nu`

@ main → i {
    : ( Vec u ) m ( vec_zeroed [u] 128 )
    ( vec_put [u] m 127 # u 1 )
    ( vec_put [u] m 0 # u 1 )
    : RsaMont c ( _rm_ctx m )
    : RsaTmp w ( _rm_tmp c )
    : ( Vec i ) a ( vec_new [i] )
    : ( Vec i ) b ( vec_new [i] )
    : ( Vec i ) d ( vec_new [i] )
    ( _rm_mul_d c w d a b )
    ( nurl_println_int ( vec_len [i] d ) )
    ^ 0
}
