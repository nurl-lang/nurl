// slhdsa_vectors.nu — SLH-DSA (FIPS 205) known-answer tests, SHAKE family.
//
// Pinned against NIST's ACVP vectors (usnistgov/ACVP-Server,
// gen-val/json-files/SLH-DSA-*-FIPS205). SLH-DSA's keys are small — a
// public key is two hashes and a private key four — so unlike ML-KEM and
// ML-DSA these cases carry their expected outputs verbatim rather than
// by digest.
//
// `tools/slhdsa_acvp_gate.sh` runs the published set. It caps how many
// signing cases it takes per group, because SLH-DSA signing is slow by
// construction; this file therefore sticks to the `f` parameter sets and
// one round trip, so it stays inside a normal build.
//
// ── What is being checked ──────────────────────────────────────────
//
// Key generation is the whole scheme in miniature: it builds the top
// XMSS tree, which means WOTS+ key generation, the Merkle hashing, and
// every address type along the way. A wrong address field or a wrong
// chain length changes the root, so a matching public key is a strong
// signal well beyond "the hash function works".
//
// The round trip then exercises FORS and the hypertree, which key
// generation never touches, and the tamper cases confirm the verifier
// is actually reading the signature rather than the key.

$ `stdlib/std/slhdsa.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ hexv s h → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex h )
    ?? r { T v → { ^ v } F _e → { ( nurl_panic `slhdsa_vectors: bad hex literal` ) ^ ( vec_new [u] ) } }
}

@ eq_hex ( Vec u ) got s want → b {
    : String x ( bytes_to_hex got )
    : b ok != 0 ( nurl_str_eq ( string_data x ) want )
    ( string_free x )
    ^ ok
}

@ report s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ kg_case s label i set s ss s sp s ps s wpk s wsk → b {
    : ( Vec u ) a ( hexv ss )
    : ( Vec u ) b2 ( hexv sp )
    : ( Vec u ) c ( hexv ps )
    : *SlhKeys k ( slhdsa_keygen_derand set a b2 c )
    : b ok1 ( eq_hex ( slhdsa_pk k ) wpk )
    : b ok2 ( eq_hex ( slhdsa_sk k ) wsk )
    : b ok3 == ( vec_len [u] ( slhdsa_pk k ) ) ( slhdsa_pk_len set )
    : b ok4 == ( vec_len [u] ( slhdsa_sk k ) ) ( slhdsa_sk_len set )
    ( slhdsa_keys_free k )
    ( vec_free [u] c ) ( vec_free [u] b2 ) ( vec_free [u] a )
    ^ ( report label & & & ok1 ok2 ok3 ok4 )
}

// A full sign/verify cycle, plus the three ways it must fail.
@ roundtrip s label i set → b {
    : ( Vec u ) a ( vec_new [u] )
    : ( Vec u ) b2 ( vec_new [u] )
    : ( Vec u ) c ( vec_new [u] )
    : ( Vec u ) msg ( vec_new [u] )
    : ( Vec u ) ctx ( vec_new [u] )
    : i n / ( slhdsa_sk_len set ) 4
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] a # u % + * i 7 set 251 )
        ( vec_push [u] b2 # u % + * i 11 5 251 )
        ( vec_push [u] c # u % + * i 13 9 251 )
        = i + i 1
    }
    = i 0
    ~ < i 40 { ( vec_push [u] msg # u % + * i 3 1 251 ) = i + i 1 }
    ( bytes_extend_str ctx `slh` )

    : *SlhKeys k ( slhdsa_keygen_derand set a b2 c )
    : ( Vec u ) sig ( slhdsa_sign_deterministic set ( slhdsa_sk k ) msg ctx )
    : b oklen == ( vec_len [u] sig ) ( slhdsa_sig_len set )
    : b okv ( slhdsa_verify set ( slhdsa_pk k ) msg ctx sig )

    // A flipped bit inside the hypertree part must not verify.
    : *u sp ( vec_data [u] sig )
    = . sp - ( vec_len [u] sig ) 100 # u ^^ # i . sp - ( vec_len [u] sig ) 100 1
    : b okbad ! ( slhdsa_verify set ( slhdsa_pk k ) msg ctx sig )
    = . sp - ( vec_len [u] sig ) 100 # u ^^ # i . sp - ( vec_len [u] sig ) 100 1

    // A different context must not verify.
    : ( Vec u ) ctx2 ( vec_new [u] )
    ( bytes_extend_str ctx2 `other` )
    : b okctx ! ( slhdsa_verify set ( slhdsa_pk k ) msg ctx2 sig )
    ( vec_free [u] ctx2 )

    // A changed message must not verify.
    : *u mp ( vec_data [u] msg )
    = . mp 0 # u ^^ # i . mp 0 1
    : b okmsg ! ( slhdsa_verify set ( slhdsa_pk k ) msg ctx sig )
    = . mp 0 # u ^^ # i . mp 0 1

    // Deterministic signing repeats exactly; that is what makes the
    // pinned vectors above reproducible at all.
    : ( Vec u ) sig2 ( slhdsa_sign_deterministic set ( slhdsa_sk k ) msg ctx )
    : b okdet ( bytes_eq sig sig2 )
    ( vec_free [u] sig2 )

    ( vec_free [u] sig )
    ( slhdsa_keys_free k )
    ( vec_free [u] ctx ) ( vec_free [u] msg )
    ( vec_free [u] c ) ( vec_free [u] b2 ) ( vec_free [u] a )
    ^ ( report label & & & & & oklen okv okbad okctx okmsg okdet )
}

@ main → i {
    : ~ b all T

    = all & all ( kg_case `keygen-128s    ` 128
    `c151951f3811029239b74add24c506af`
    `dd30363e156e6fe936ec6ed0231feb5c`
    `529ffe86200d1f32c2b60d0cd909f190`
    `529ffe86200d1f32c2b60d0cd909f1900761f9b727afa724b47223016bb5b2ba`
    `c151951f3811029239b74add24c506afdd30363e156e6fe936ec6ed0231feb5c529ffe86200d1f32c2b60d0cd909f1900761f9b727afa724b47223016bb5b2ba` )

    = all & all ( kg_case `keygen-128f    ` 129
    `3956ab391b4d22fc907af0740326d061`
    `ab0eb206436f2b86ebe086d77739b3e4`
    `56505c229f4e7fa6b201714c7dcc9da3`
    `56505c229f4e7fa6b201714c7dcc9da366578f1f24c3fe371c97c14ce0e79cdc`
    `3956ab391b4d22fc907af0740326d061ab0eb206436f2b86ebe086d77739b3e456505c229f4e7fa6b201714c7dcc9da366578f1f24c3fe371c97c14ce0e79cdc` )

    = all & all ( kg_case `keygen-192f    ` 193
    `fb7a2c2c75ce6c96b5f4328e0ab300476fc6f864cb5b0b99`
    `990ecb726ca822a4e3652dd92ec0aab7637ea41c0482ae28`
    `68dcc671e3534f81a352c275b6a25f906d2ed0ff62b8b4e3`
    `68dcc671e3534f81a352c275b6a25f906d2ed0ff62b8b4e398f1a9876cb082a48e9ae2c862b289486a3925cefc6ff4be`
    `fb7a2c2c75ce6c96b5f4328e0ab300476fc6f864cb5b0b99990ecb726ca822a4e3652dd92ec0aab7637ea41c0482ae2868dcc671e3534f81a352c275b6a25f906d2ed0ff62b8b4e398f1a9876cb082a48e9ae2c862b289486a3925cefc6ff4be` )

    // 256f is the one parameter set whose hypertree index fills all 64
    // bits (h − h/d = 68 − 4). It is here because a signed-shift mask
    // pinned every tree index to zero at exactly this set and nowhere
    // else, and only its vectors caught it.
    = all & all ( kg_case `keygen-256f    ` 257
    `2ac9403858d186b172edd8df9c78a11449893681487d3af0dad0ec341e8aca48`
    `afa2771bae6c17dd6f77b4e3808b05f56f31b8f4128df2ccb677f0283cfb18da`
    `559bc883105e8ba0264648b532626155f87edb4bedcfc12a24204d3b696d5370`
    `559bc883105e8ba0264648b532626155f87edb4bedcfc12a24204d3b696d53707a158ff5d30e3428183a3b3a96a0e4a341a2a16e5a6226af374d1efb39a35df6`
    `2ac9403858d186b172edd8df9c78a11449893681487d3af0dad0ec341e8aca48afa2771bae6c17dd6f77b4e3808b05f56f31b8f4128df2ccb677f0283cfb18da559bc883105e8ba0264648b532626155f87edb4bedcfc12a24204d3b696d53707a158ff5d30e3428183a3b3a96a0e4a341a2a16e5a6226af374d1efb39a35df6` )

    = all & all ( roundtrip `roundtrip-128f ` 129 )

    ^ ? all 0 1
}
