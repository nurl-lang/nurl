// packages/swarm-mcp/tests/work_test.nu — offline tests for the map-reduce.
// Verifies the kernel handler and that sharding reproduces the whole-range
// answer for every reduce op. Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/work_test.nu /tmp/wt && /tmp/wt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/token.nu`
$ `src/expr.nu`
$ `src/work.nu`

// Shard [lo,hi) into n, run the kernel handler on each chunk, combine. Payloads
// and results are HMAC-tagged with the cluster key exactly as on the wire.
@ shard_run i op i lo i hi s expr i n → i {
    : ( Vec u ) key ( token_key `test-token` )
    : ( @ ( Vec u ) ( Vec u ) ) h ( kernel_handler key )
    : ( Vec u ) eb ( bytes_from_str expr )
    : ( Vec s ) cs ( shard lo hi n )
    : ~ i acc ( red_id op )
    : ~ i k 0
    ~ < k n {
        : *Chunk c # *Chunk ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        : ( Vec u ) pl ( chunk_payload op 0 . c lo . c hi eb )
        : ( Vec u ) tagged ( token_tag key pl )
        : ( Vec u ) r ( h tagged )
        ?? ( token_untag key r ) {
            T body → { = acc ( red_combine op acc ( result_decode body ) ) ( vec_free [u] body ) }
            F → {}
        }
        ( vec_free [u] r ) ( vec_free [u] tagged ) ( vec_free [u] pl )
        = k + k 1
    }
    ( shard_free cs ) ( vec_free [u] eb ) ( vec_free [u] key )
    : *u env # *u h 1
    ? != # i env 0 { ( nurl_free # s env ) } {}
    ^ acc
}

// Float dual of shard_run: dtype=1 chunks, partials decoded from f64 bits and
// combined in f64. Returns the combined double.
@ shard_run_f i op i lo i hi s expr i n → f {
    : ( Vec u ) key ( token_key `test-token` )
    : ( @ ( Vec u ) ( Vec u ) ) h ( kernel_handler key )
    : ( Vec u ) eb ( bytes_from_str expr )
    : ( Vec s ) cs ( shard lo hi n )
    : ~ f acc ( red_id_f op )
    : ~ i k 0
    ~ < k n {
        : *Chunk c # *Chunk ?? ( vec_get [s] cs k ) { T x → x F → # s 0 }
        : ( Vec u ) pl ( chunk_payload op 1 . c lo . c hi eb )
        : ( Vec u ) tagged ( token_tag key pl )
        : ( Vec u ) r ( h tagged )
        ?? ( token_untag key r ) {
            T body → { = acc ( red_combine_f op acc ( bits_to_f64 ( result_decode body ) ) ) ( vec_free [u] body ) }
            F → {}
        }
        ( vec_free [u] r ) ( vec_free [u] tagged ) ( vec_free [u] pl )
        = k + k 1
    }
    ( shard_free cs ) ( vec_free [u] eb ) ( vec_free [u] key )
    : *u env # *u h 1
    ? != # i env 0 { ( nurl_free # s env ) } {}
    ^ acc
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

// Float assert: pass if |a-b| < tol.
@ pf s label f a f b f tol → v {
    : f d - a b
    : f ad ? < d 0.0 - 0.0 d d
    ( nurl_print label ) ( nurl_print ( nurl_str_float a ) )
    ( nurl_print ? < ad tol ` ~= ` ` != ` ) ( nurl_print ( nurl_str_float b ) ) ( nurl_print `\n` )
}

@ main → i {
    // whole-range answers
    ( pi `sum x*x [1,11):       ` ( shard_run ( red_sum ) 1 11 `x*x` 1 ) 385 )
    ( pi `count x%2==0 [0,10):  ` ( shard_run ( red_count ) 0 10 `x%2==0` 1 ) 5 )
    ( pi `product x [1,6):      ` ( shard_run ( red_product ) 1 6 `x` 1 ) 120 )
    ( pi `max x*x-7*x [0,11):   ` ( shard_run ( red_max ) 0 11 `x*x-7*x` 1 ) 30 )
    ( pi `min x*x-7*x [0,11):   ` ( shard_run ( red_min ) 0 11 `x*x-7*x` 1 ) -12 )

    // sharding must reproduce the whole-range answer for any chunk count
    ( pi `sum sharded n=7:      ` ( shard_run ( red_sum ) 1 11 `x*x` 7 ) 385 )
    ( pi `sum sharded n=64:     ` ( shard_run ( red_sum ) 1 11 `x*x` 64 ) 385 )
    ( pi `count sharded n=4:    ` ( shard_run ( red_count ) 0 10 `x%2==0` 4 ) 5 )
    ( pi `count sharded n=13:   ` ( shard_run ( red_count ) 0 10 `x%2==0` 13 ) 5 )
    ( pi `product sharded n=3:  ` ( shard_run ( red_product ) 1 6 `x` 3 ) 120 )
    ( pi `max sharded n=5:      ` ( shard_run ( red_max ) 0 11 `x*x-7*x` 5 ) 30 )
    ( pi `min sharded n=5:      ` ( shard_run ( red_min ) 0 11 `x*x-7*x` 5 ) -12 )
    ( pi `max sharded n>range:  ` ( shard_run ( red_max ) 0 11 `x*x-7*x` 40 ) 30 )

    // a bigger sum to exercise real iteration: Σ x for x in [0,1000) = 499500
    ( pi `sum x [0,1000) n=8:   ` ( shard_run ( red_sum ) 0 1000 `x` 8 ) 499500 )

    // ── float (dtype=1) folds, incl. sharding-associativity ──────
    ( pf `f sum x*0.5 [0,10):   ` ( shard_run_f ( red_sum ) 0 10 `x*0.5` 1 ) 22.5 0.000001 )
    ( pf `f sum sharded n=8:    ` ( shard_run_f ( red_sum ) 0 10 `x*0.5` 8 ) 22.5 0.000001 )
    ( pf `f product 1.5 [0,3):  ` ( shard_run_f ( red_product ) 0 3 `1.5` 1 ) 3.375 0.000001 )
    ( pf `f product sharded n=3:` ( shard_run_f ( red_product ) 0 3 `1.5` 3 ) 3.375 0.000001 )
    ( pf `f max x*0.1 [0,11):   ` ( shard_run_f ( red_max ) 0 11 `x*0.1` 5 ) 1.0 0.000001 )
    ( pf `f min -x*0.1 [0,11):  ` ( shard_run_f ( red_min ) 0 11 `-x*0.1` 5 ) -1.0 0.000001 )
    // Basel: Σ 1/k² for k in [1,1001) ≈ 1.6439346; sharding must reproduce it.
    ( pf `f Basel [1,1001) n=1: ` ( shard_run_f ( red_sum ) 1 1001 `1.0/(x*x)` 1 ) 1.6439346 0.00001 )
    ( pf `f Basel sharded n=16: ` ( shard_run_f ( red_sum ) 1 1001 `1.0/(x*x)` 16 ) 1.6439346 0.00001 )
    ^ 0
}
