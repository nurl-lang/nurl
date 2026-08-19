// bench/pq.nu — the post-quantum stack, measured. Run directly:
//
//     ./nurl.sh -O2 bench/pq.nu bench/_build/pq && bench/_build/pq
//
// Covers the three FIPS schemes at the parameter sets that matter in
// practice: ML-KEM-768 (the KEM inside X25519MLKEM768, the hybrid TLS
// group Chrome and Cloudflare deploy), ML-DSA-65 and -44 (certificate
// signatures), and SLH-DSA-SHAKE-128f (the hash-based fallback whose
// security assumes nothing but SHAKE). SHAKE128 bulk throughput is
// first because every scheme above is mostly made of it.
//
// The bar these numbers are held to was measured on the same host
// (i7-5930K @ 3.5 GHz, 2026-08-19) against the scheme authors' own
// implementations built from source — pq-crystals/kyber,
// pq-crystals/dilithium and sphincs/sphincsplus, both their reference C
// and their hand-written AVX2:
//
//     µs/op                pure NURL    their ref C    their AVX2
//     ML-KEM-768 keygen        30           47             11.8
//                encaps        30           63             11.7
//                decaps        38           79             12.5
//     ML-DSA-65  sign         286          569            113
//                verify        85          160             45
//     SLH-DSA-128f keygen     656         4696           1104
//                  sign     19807       112721          25546
//                  verify     1616         7953           1894
//
// Pure NURL beats the reference C everywhere, and beats the AVX2
// implementations on every SLH-DSA operation — the scheme that is
// almost nothing but Keccak, which stdlib runs four lanes at a time
// (std/hash_sha3x4) behind the `simd` prefix. The lattice schemes sit
// at 2–3× from AVX2; what remains there is hand-packed shuffling below
// vector width in the NTT's narrow layers and the compress/encode bit
// cursors — measured, known, and cheaper to leave than to hold badly.
//
// Every algorithm here is pinned byte-exact by NIST ACVP vectors
// (tools/*_acvp_gate.nu), so this file only has to be honest about
// speed, not correctness.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bench.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/slhdsa.nu`

: ~ i g_sink 0

@ __msg i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v & 255 * i 7 ) = i + i 1 }
    ^ v
}

@ __shake_bulk → v {
    : i MB 8
    : ( Vec u ) buf ( __msg * MB 1048576 )
    : i t0 ( monotonic_ns )
    : ( Vec u ) o ( shake128_pure buf 32 )
    : i t1 ( monotonic_ns )
    = g_sink + g_sink ( vec_len [u] o )
    ( vec_free [u] o ) ( vec_free [u] buf )
    : String ln ( string_new )
    ( string_push_str ln `shake128 absorb              ` )
    ( string_push_int ln / * * MB 1000 1000000 - t1 t0 )
    ( string_push_str ln ` MB/s\n` )
    ( nurl_print ( string_data ln ) )
    ( string_free ln )
}

@ __mlkem768 → v {
    : BenchResult kg ( bench_auto `ML-KEM-768 keygen` \ → v {
        : *MlkemKeys k ( mlkem_keygen 768 )
        = g_sink + g_sink ( vec_len [u] ( mlkem_ek k ) )
        ( mlkem_keys_free k )
    } )
    ( bench_report kg ) ( bench_result_free kg )

    : *MlkemKeys ks ( mlkem_keygen 768 )
    : BenchResult en ( bench_auto `ML-KEM-768 encaps` \ → v {
        : *MlkemEncap e ( mlkem_encaps 768 ( mlkem_ek ks ) )
        = g_sink + g_sink ( vec_len [u] ( mlkem_ct e ) )
        ( mlkem_encap_free e )
    } )
    ( bench_report en ) ( bench_result_free en )

    : *MlkemEncap e2 ( mlkem_encaps 768 ( mlkem_ek ks ) )
    : BenchResult de ( bench_auto `ML-KEM-768 decaps` \ → v {
        : ( Vec u ) ss ( mlkem_decaps 768 ( mlkem_dk ks ) ( mlkem_ct e2 ) )
        = g_sink + g_sink ( vec_len [u] ss )
        ( vec_free [u] ss )
    } )
    ( bench_report de ) ( bench_result_free de )
    ( mlkem_encap_free e2 )
    ( mlkem_keys_free ks )
}

@ __mldsa i level → v {
    : ( Vec u ) msg ( __msg 1024 )
    : ( Vec u ) ctx ( vec_new [u] )
    : String nm ( string_new )
    ( string_push_str nm `ML-DSA-` )
    ( string_push_int nm level )

    : *MldsaKeys ks ( mldsa_keygen level )
    : String snm ( string_new )
    ( string_push_str snm ( string_data nm ) )
    ( string_push_str snm ` sign` )
    : BenchResult sg ( bench_auto ( string_data snm ) \ → v {
        : ( Vec u ) sig ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
        = g_sink + g_sink ( vec_len [u] sig )
        ( vec_free [u] sig )
    } )
    ( bench_report sg ) ( bench_result_free sg ) ( string_free snm )

    : ( Vec u ) sig ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
    : String vnm ( string_new )
    ( string_push_str vnm ( string_data nm ) )
    ( string_push_str vnm ` verify` )
    : BenchResult vf ( bench_auto ( string_data vnm ) \ → v {
        ? ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig ) { = g_sink + g_sink 1 } {}
    } )
    ( bench_report vf ) ( bench_result_free vf ) ( string_free vnm )

    ( vec_free [u] sig )
    ( mldsa_keys_free ks )
    ( string_free nm )
    ( vec_free [u] ctx ) ( vec_free [u] msg )
}

@ __slhdsa128f → v {
    : i set ( slhdsa_set_128f )
    : ( Vec u ) msg ( __msg 1024 )
    : ( Vec u ) ctx ( vec_new [u] )

    : BenchResult kg ( bench_run `SLH-DSA-128f keygen` 20 \ → v {
        : *SlhKeys k ( slhdsa_keygen set )
        = g_sink + g_sink ( vec_len [u] ( slhdsa_pk k ) )
        ( slhdsa_keys_free k )
    } )
    ( bench_report kg ) ( bench_result_free kg )

    : *SlhKeys ks ( slhdsa_keygen set )
    : BenchResult sg ( bench_run `SLH-DSA-128f sign` 5 \ → v {
        : ( Vec u ) sig ( slhdsa_sign set ( slhdsa_sk ks ) msg ctx )
        = g_sink + g_sink ( vec_len [u] sig )
        ( vec_free [u] sig )
    } )
    ( bench_report sg ) ( bench_result_free sg )

    : ( Vec u ) sig ( slhdsa_sign set ( slhdsa_sk ks ) msg ctx )
    : BenchResult vf ( bench_run `SLH-DSA-128f verify` 40 \ → v {
        ? ( slhdsa_verify set ( slhdsa_pk ks ) msg ctx sig ) { = g_sink + g_sink 1 } {}
    } )
    ( bench_report vf ) ( bench_result_free vf )

    ( vec_free [u] sig )
    ( slhdsa_keys_free ks )
    ( vec_free [u] ctx ) ( vec_free [u] msg )
}

@ main → v {
    ( __shake_bulk )
    ( __mlkem768 )
    ( __mldsa 44 )
    ( __mldsa 65 )
    ( __slhdsa128f )
    ? < g_sink 0 { ( nurl_print `` ) } {}
}
