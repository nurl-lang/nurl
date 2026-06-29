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
        : ( Vec u ) pl ( chunk_payload op . c lo . c hi eb )
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

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
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
    ^ 0
}
