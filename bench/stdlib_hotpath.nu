// bench/stdlib_hotpath.nu — micro-benchmarks for a few stdlib hot
// paths, driven by std/bench.nu. Run directly (`./nurl.sh -O2
// bench/stdlib_hotpath.nu bench && ./bench`) or via `nurlpkg bench`
// from a project whose benches/ links here. Reports ns/op and the
// NURL-level allocations/op for each.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/cmp.nu`
$ `stdlib/std/bench.nu`

@ main → i {
    ( nurl_print `stdlib hot-path benchmarks (ns/op, allocs/op):\n\n` )

    // 1. String building: 16 push_char into a pre-sized buffer.
    : ( @ v ) b_str \ → v {
        : String s ( string_with_cap 16 )
        : ~ i k 0
        ~ < k 16 { ( string_push_char s + 97 % k 26 ) = k + k 1 }
        ( string_free s )
    }
    : BenchResult r1 ( bench_auto `string_build_16` b_str )
    ( bench_report r1 ) ( bench_result_free r1 )

    // 2. Vec push: 64 i64s into a growing vector (amortised reallocs).
    : ( @ v ) b_vec \ → v {
        : ( Vec i ) v ( vec_new [i] )
        : ~ i k 0
        ~ < k 64 { ( vec_push [i] v * k k ) = k + k 1 }
        ( vec_free [i] v )
    }
    : BenchResult r2 ( bench_auto `vec_push_64` b_vec )
    ( bench_report r2 ) ( bench_result_free r2 )

    // 3. Sort: 32 descending i64s back to ascending each op.
    : ( @ i i i ) ci \ i a i b → i { ^ ( cmp_int a b ) }
    : ( @ v ) b_sort \ → v {
        : ( Vec i ) v ( vec_with_cap [i] 32 )
        : ~ i k 0
        ~ < k 32 { ( vec_push [i] v - 32 k ) = k + k 1 }
        ( sort_by [i] v ci )
        ( vec_free [i] v )
    }
    : BenchResult r3 ( bench_auto `sort_32_desc` b_sort )
    ( bench_report r3 ) ( bench_result_free r3 )

    ^ 0
}
