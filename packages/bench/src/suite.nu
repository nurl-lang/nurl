// packages/bench/src/suite.nu — the benchmarks themselves. Each returns a
// BenchRow measured on this machine, right now. Everything is pure NURL and
// self-contained: the inputs are generated deterministically at setup (that
// work is not timed — std/bench snapshots the clock and the allocation
// counter around the timed loop only), no file, model, GPU or network is
// touched, and there are no dependencies beyond the standard library.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/cbor.nu`
$ `src/report.nu`

// ---- deterministic input generators (setup, never timed) --------------

// n pseudo-random bytes (a seeded xorshift, so the buffer is identical run
// to run and machine to machine)
@ __gen_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i s 88172645463325252
    : ~ i k 0
    ~ < k n {
        = s ^^ s << s 13
        = s ^^ s >> s 7
        = s ^^ s << s 17
        ( vec_push [u] v # u & s 255 )
        = k + k 1
    }
    ^ v
}

// n seeded i64s in [0, 1e9) — an unsorted column to sort
@ __gen_ints i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : Rng g ( rng_seed 2463534242 )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] v ( rng_below g 1000000000 ) )
        = k + k 1
    }
    ( rng_free g )
    ^ v
}

// A JSON array of `m` small objects, stringified to a parseable document.
@ __gen_json_doc i m → String {
    : Json arr ( json_arr_new )
    : ~ i k 0
    ~ < k m {
        : Json o ( json_obj_new )
        : b _a ( json_obj_set o `id` ( json_int k ) )
        : b _b ( json_obj_set o `name` ( json_str_lit `benchmark-item` ) )
        : b _c ( json_obj_set o `value` ( json_int * k 7 ) )
        : b _d ( json_obj_set o `enabled` ( json_bool ? == & k 1 0 T F ) )
        : b _e ( json_arr_push arr o )
        = k + k 1
    }
    : String txt ( json_stringify arr )
    ( json_free arr )
    ^ txt
}

// A UTF-8 string of roughly `n` bytes, mixing ASCII and multi-byte runes so
// utf8_decode does real continuation-byte work.
@ __gen_utf8 i n → String {
    : String out ( string_with_cap + n 8 )
    ~ < ( string_len out ) n {
        ( string_push_str out `the quick brown fox — héllo, wörld ☃ 日本語 ` )
    }
    ^ out
}

// f-or-0 read (Vec i length-1 accumulators can't be dead-code eliminated)
@ __ipeek ( Vec i ) v i idx → i {
    ?? ( vec_get [i] v idx ) { T x → { ^ x } F → { ^ 0 } }
}

// ---- the benchmarks ---------------------------------------------------

@ bench_sha256 → BenchRow {
    : i n 1048576
    : ( Vec u ) buf ( __gen_bytes n )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `sha256` n `MB/s` \ → v {
        : *Sha256 h ( sha256_init )
        ( sha256_update h buf )
        : ( Vec u ) d ( sha256_final h )
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( vec_len [u] d ) )
        ( vec_free [u] d )
    } )
    ( vec_free [u] buf )
    ( vec_free [i] sink )
    ^ r
}

@ bench_json_parse → BenchRow {
    : String doc ( __gen_json_doc 1200 )
    : i bytes ( string_len doc )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `json parse` bytes `MB/s` \ → v {
        ?? ( json_parse ( string_data doc ) ) {
            T j → {
                ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( json_arr_len j ) )
                ( json_free j )
            }
            F _ → {}
        }
    } )
    ( string_free doc )
    ( vec_free [i] sink )
    ^ r
}

@ bench_sort → BenchRow {
    : i n 50000
    : ( Vec i ) base ( __gen_ints n )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `sort i64` n `M/s` \ → v {
        : ( Vec i ) c ( vec_clone [i] base )
        ( sort_by [i] c \ i a i b → i { ^ - a b } )
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( __ipeek c 0 ) )
        ( vec_free [i] c )
    } )
    ( vec_free [i] base )
    ( vec_free [i] sink )
    ^ r
}

@ bench_cbor_decode → BenchRow {
    : Json doc ( json_arr_new )
    : ~ i k 0
    ~ < k 2000 {
        ( json_arr_push doc ( json_int * k 3 ) )
        = k + k 1
    }
    : ~ ( Vec u ) enc ( vec_new [u] )
    ?? ( cbor_encode doc ) { T v → { ( vec_free [u] enc ) = enc v } F _ → {} }
    ( json_free doc )
    : i bytes ( vec_len [u] enc )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `cbor decode` bytes `MB/s` \ → v {
        ?? ( cbor_decode enc ) {
            T j → {
                ( vec_set [i] sink 0 + ( __ipeek sink 0 ) ( json_arr_len j ) )
                ( json_free j )
            }
            F _ → {}
        }
    } )
    ( vec_free [u] enc )
    ( vec_free [i] sink )
    ^ r
}

@ bench_utf8_decode → BenchRow {
    : String s ( __gen_utf8 262144 )
    : i bytes ( string_len s )
    : s sd ( string_data s )
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    : BenchRow r ( bench_thpt `utf8 decode` bytes `MB/s` \ → v {
        : ~ i pos 0
        : ~ i cps 0
        ~ < pos bytes {
            : Utf8Dec d ( utf8_decode sd pos )
            : i w ? > . d width 0 . d width 1
            = pos + pos w
            = cps + cps 1
        }
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) cps )
    } )
    ( string_free s )
    ( vec_free [i] sink )
    ^ r
}

@ bench_int_loop → BenchRow {
    : i n 2000000
    : ( Vec i ) sink ( vec_new [i] )
    ( vec_push [i] sink 0 )
    // a data-dependent xorshift mix per iteration: the feedback through the
    // shifts is non-polynomial, so the optimiser cannot collapse the loop to
    // a closed form (a plain sum would be evaluated at compile time and
    // measure nothing).
    : BenchRow r ( bench_thpt `int loop` n `M/s` \ → v {
        : ~ i acc 1
        : ~ i k 0
        ~ < k n {
            = acc ^^ acc << acc 13
            = acc ^^ acc >> acc 7
            = acc + acc k
            = k + k 1
        }
        ( vec_set [i] sink 0 + ( __ipeek sink 0 ) acc )
    } )
    ( vec_free [i] sink )
    ^ r
}
