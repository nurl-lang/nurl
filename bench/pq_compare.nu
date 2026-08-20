// bench/pq_compare.nu — the NURL half of the post-quantum peer
// comparison (bench/run_pq.sh drives this against bench/rust_pq).
//
// Same schemes and measurement discipline as bench/pq.nu (bench_auto
// for the lattice ops, fixed-iteration bench_run for SLH-DSA whose
// single ops already clear the calibration window), but the output is
// machine-readable TSV for bench/gen_pq_results.py instead of prose:
//
//     ROW\t<name>\t<ns_per_op>\t<iters>
//     THR\t<name>\t<mb_per_s>
//
// Keep the operation names in lockstep with bench/rust_pq/src/main.rs —
// the report generator joins the two outputs on the name column.
//
// Correctness is pinned elsewhere (NIST ACVP vectors, tools/*_acvp_gate
// .nu); this file only measures.

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

// One `ROW\tname\tns_per_op\titers` line from a finished measurement.
@ __row BenchResult r → v {
    : String ln ( string_new )
    ( string_push_str ln `ROW\t` )
    ( string_push_str ln ( bench_result_name r ) )
    ( string_push_str ln `\t` )
    ( string_push_int ln ( bench_result_ns_per_op r ) )
    ( string_push_str ln `\t` )
    ( string_push_int ln ( bench_result_iters r ) )
    ( string_push_str ln `\n` )
    ( nurl_print ( string_data ln ) )
    ( string_free ln )
}

// `<base> <op>` scratch name; caller frees.
@ __opname s base s op → String {
    : String nm ( string_new )
    ( string_push_str nm base )
    ( string_push_str nm ` ` )
    ( string_push_str nm op )
    ^ nm
}

// SHAKE128 bulk absorb: 8 MB, one warmup pass, best of 3 timed passes
// (bulk hashing has no per-op variance worth a median; best-of filters
// scheduler noise the same way bench/pq.nu's single pass could not).
@ __shake_bulk → v {
    : i MB 8
    : ( Vec u ) buf ( __msg * MB 1048576 )
    : ( Vec u ) w ( shake128_pure buf 32 )
    = g_sink + g_sink ( vec_len [u] w )
    ( vec_free [u] w )
    : ~ i best 0
    : ~ i pass 0
    ~ < pass 3 {
        : i t0 ( monotonic_ns )
        : ( Vec u ) o ( shake128_pure buf 32 )
        : i t1 ( monotonic_ns )
        = g_sink + g_sink ( vec_len [u] o )
        ( vec_free [u] o )
        : i dt - t1 t0
        ? | == best 0 < dt best { = best dt } {}
        = pass + pass 1
    }
    ( vec_free [u] buf )
    : String ln ( string_new )
    ( string_push_str ln `THR\tSHAKE128 absorb 8 MB\t` )
    ( string_push_int ln / * * MB 1000 1000000 best )
    ( string_push_str ln `\n` )
    ( nurl_print ( string_data ln ) )
    ( string_free ln )
}

@ __mlkem i level → v {
    : String base ( string_new )
    ( string_push_str base `ML-KEM-` )
    ( string_push_int base level )

    : String knm ( __opname ( string_data base ) `keygen` )
    : BenchResult kg ( bench_auto ( string_data knm ) \ → v {
        : *MlkemKeys k ( mlkem_keygen level )
        = g_sink + g_sink ( vec_len [u] ( mlkem_ek k ) )
        ( mlkem_keys_free k )
    } )
    ( __row kg ) ( bench_result_free kg ) ( string_free knm )

    : *MlkemKeys ks ( mlkem_keygen level )
    : String enm ( __opname ( string_data base ) `encaps` )
    : BenchResult en ( bench_auto ( string_data enm ) \ → v {
        : *MlkemEncap e ( mlkem_encaps level ( mlkem_ek ks ) )
        = g_sink + g_sink ( vec_len [u] ( mlkem_ct e ) )
        ( mlkem_encap_free e )
    } )
    ( __row en ) ( bench_result_free en ) ( string_free enm )

    : *MlkemEncap e2 ( mlkem_encaps level ( mlkem_ek ks ) )
    : String dnm ( __opname ( string_data base ) `decaps` )
    : BenchResult de ( bench_auto ( string_data dnm ) \ → v {
        : ( Vec u ) ss ( mlkem_decaps level ( mlkem_dk ks ) ( mlkem_ct e2 ) )
        = g_sink + g_sink ( vec_len [u] ss )
        ( vec_free [u] ss )
    } )
    ( __row de ) ( bench_result_free de ) ( string_free dnm )
    ( mlkem_encap_free e2 )
    ( mlkem_keys_free ks )
    ( string_free base )
}

@ __mldsa i level → v {
    : ( Vec u ) msg ( __msg 1024 )
    : ( Vec u ) ctx ( vec_new [u] )
    : String base ( string_new )
    ( string_push_str base `ML-DSA-` )
    ( string_push_int base level )

    : String knm ( __opname ( string_data base ) `keygen` )
    : BenchResult kg ( bench_auto ( string_data knm ) \ → v {
        : *MldsaKeys k ( mldsa_keygen level )
        = g_sink + g_sink ( vec_len [u] ( mldsa_pk k ) )
        ( mldsa_keys_free k )
    } )
    ( __row kg ) ( bench_result_free kg ) ( string_free knm )

    : *MldsaKeys ks ( mldsa_keygen level )
    : String snm ( __opname ( string_data base ) `sign` )
    : BenchResult sg ( bench_auto ( string_data snm ) \ → v {
        : ( Vec u ) sig ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
        = g_sink + g_sink ( vec_len [u] sig )
        ( vec_free [u] sig )
    } )
    ( __row sg ) ( bench_result_free sg ) ( string_free snm )

    : ( Vec u ) sig ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
    : String vnm ( __opname ( string_data base ) `verify` )
    : BenchResult vf ( bench_auto ( string_data vnm ) \ → v {
        ? ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig ) { = g_sink + g_sink 1 } {}
    } )
    ( __row vf ) ( bench_result_free vf ) ( string_free vnm )

    ( vec_free [u] sig )
    ( mldsa_keys_free ks )
    ( string_free base )
    ( vec_free [u] ctx ) ( vec_free [u] msg )
}

// SLH-DSA at one parameter set. Fixed iteration counts (per op) because
// a single signing op is already tens of milliseconds — bench_auto's
// calibration ramp would just burn the time budget re-measuring.
@ __slh i set s label i kgn i sgn i vfn → v {
    : ( Vec u ) msg ( __msg 1024 )
    : ( Vec u ) ctx ( vec_new [u] )
    : String base ( string_new )
    ( string_push_str base `SLH-DSA-SHAKE-` )
    ( string_push_str base label )

    : String knm ( __opname ( string_data base ) `keygen` )
    : BenchResult kg ( bench_run ( string_data knm ) kgn \ → v {
        : *SlhKeys k ( slhdsa_keygen set )
        = g_sink + g_sink ( vec_len [u] ( slhdsa_pk k ) )
        ( slhdsa_keys_free k )
    } )
    ( __row kg ) ( bench_result_free kg ) ( string_free knm )

    : *SlhKeys ks ( slhdsa_keygen set )
    : String snm ( __opname ( string_data base ) `sign` )
    : BenchResult sg ( bench_run ( string_data snm ) sgn \ → v {
        : ( Vec u ) sig ( slhdsa_sign set ( slhdsa_sk ks ) msg ctx )
        = g_sink + g_sink ( vec_len [u] sig )
        ( vec_free [u] sig )
    } )
    ( __row sg ) ( bench_result_free sg ) ( string_free snm )

    : ( Vec u ) sig ( slhdsa_sign set ( slhdsa_sk ks ) msg ctx )
    : String vnm ( __opname ( string_data base ) `verify` )
    : BenchResult vf ( bench_run ( string_data vnm ) vfn \ → v {
        ? ( slhdsa_verify set ( slhdsa_pk ks ) msg ctx sig ) { = g_sink + g_sink 1 } {}
    } )
    ( __row vf ) ( bench_result_free vf ) ( string_free vnm )

    ( vec_free [u] sig )
    ( slhdsa_keys_free ks )
    ( string_free base )
    ( vec_free [u] ctx ) ( vec_free [u] msg )
}

@ main → v {
    ( __shake_bulk )
    ( __mlkem 512 ) ( __mlkem 768 ) ( __mlkem 1024 )
    ( __mldsa 44 ) ( __mldsa 65 ) ( __mldsa 87 )
    ( __slh ( slhdsa_set_128s ) `128s` 3 2 10 )
    ( __slh ( slhdsa_set_128f ) `128f` 20 5 40 )
    ( __slh ( slhdsa_set_192f ) `192f` 10 3 20 )
    ( __slh ( slhdsa_set_256f ) `256f` 5 2 10 )
    ? < g_sink 0 { ( nurl_print `` ) } {}
}
