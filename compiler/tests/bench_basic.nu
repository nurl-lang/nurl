// bench_basic.nu — std/bench.nu acceptance for its deterministic
// surface. Wall-time (ns/op) is machine-dependent, so the golden checks
// only: the report formatting (pure), the allocation counter (a
// vec_new+free cycle allocates a fixed amount per op; a no-op body
// allocates none), iteration bookkeeping, and that ns/op is non-negative.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bench.nu`

@ main → i {
    // pure formatting
    : String f ( __bench_fmt `demo` 1000 42 3 )
    ( nurl_print ( string_data f ) ) ( nurl_print `\n` )
    ( string_free f )

    // vec_new + vec_free allocates a fixed number of NURL blocks per op
    : ( @ v ) alloc_body \ → v { : ( Vec i ) v ( vec_new [i] ) ( vec_free [i] v ) }
    : BenchResult r1 ( bench_run `vec_cycle` 1000 alloc_body )
    ( nurl_print `vec_allocs_per_op=` ) ( nurl_print ( nurl_str_int ( bench_result_allocs_per_op r1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `iters=` ) ( nurl_print ( nurl_str_int ( bench_result_iters r1 ) ) ) ( nurl_print `\n` )
    ( nurl_print `ns_nonneg=` ) ( nurl_print ? >= ( bench_result_ns_per_op r1 ) 0 `T` `F` ) ( nurl_print `\n` )
    ( bench_result_free r1 )

    // a body that allocates nothing → 0 allocs/op
    : ( @ v ) noalloc \ → v { : i _x + 1 2 }
    : BenchResult r2 ( bench_run `noop` 1000 noalloc )
    ( nurl_print `noop_allocs_per_op=` ) ( nurl_print ( nurl_str_int ( bench_result_allocs_per_op r2 ) ) ) ( nurl_print `\n` )
    ( bench_result_free r2 )
    ^ 0
}
