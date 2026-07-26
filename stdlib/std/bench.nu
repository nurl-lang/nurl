// stdlib/std/bench.nu — a micro-benchmark harness.
//
// Time a closure over many iterations and report ns/op plus the
// NURL-level allocations/op (vec/string/struct ctl blocks all route
// through nurl_alloc, which the runtime counts). Wall time comes from
// the monotonic clock (`monotonic_ns`), so it is immune to NTP slew.
//
//   ( bench_run  s name i iters ( @ v ) body )  → BenchResult
//   ( bench_auto s name ( @ v ) body )           → BenchResult
//       auto-scales iters until a timed run clears ~50 ms, for stable
//       ns/op on cheap operations.
//   ( bench_report BenchResult r )               → v   one line to stdout
//   ( bench_result_ns_per_op  BenchResult r )    → i
//   ( bench_result_allocs_per_op BenchResult r ) → i
//   ( bench_result_free BenchResult r )          → v
//
// Each run does a short untimed warmup first (caches/branch predictor),
// then snapshots the allocation counter and clock around the timed
// loop, so warmup work is excluded from both metrics. `body` takes no
// arguments and returns nothing — capture inputs/outputs in its
// environment (a `~`-mutable accumulator defeats dead-code elimination
// of the work being measured).

$ `stdlib/core/string.nu`
$ `stdlib/std/time.nu`

// Runtime allocation counter (stdlib/runtime.c §9). Monotonic, process-
// wide; subtract two snapshots for a delta.
& `libc` @ nurl_alloc_count → i

: BenchResult { String name i iters i total_ns i ns_per_op i allocs_per_op }

@ bench_result_name BenchResult r → s { ^ ( string_data . r name ) }

@ bench_result_iters BenchResult r → i { ^ . r iters }

@ bench_result_total_ns BenchResult r → i { ^ . r total_ns }

@ bench_result_ns_per_op BenchResult r → i { ^ . r ns_per_op }

@ bench_result_allocs_per_op BenchResult r → i { ^ . r allocs_per_op }

@ bench_result_free BenchResult r → v { ( string_free . r name ) }

// Run `body` `iters` times (after a short warmup) and measure.
@ bench_run s name i iters ( @ v ) body → BenchResult {
    : i n ? > iters 0 iters 1
    // warmup: ~1% of iters, at least 1, capped so it stays cheap
    : i warm ? > / n 100 0 / n 100 1
    : ~ i w 0
    ~ < w warm { ( body ) = w + w 1 }

    : i a0 ( nurl_alloc_count )
    : i t0 ( monotonic_ns )
    : ~ i k 0
    ~ < k n { ( body ) = k + k 1 }
    : i t1 ( monotonic_ns )
    : i a1 ( nurl_alloc_count )

    : i total ? > - t1 t0 0 - t1 t0 0
    : String nm ( string_with_cap + ( nurl_str_len name ) 1 )
    ( string_push_str nm name )
    ^ @ BenchResult { nm n total / total n / - a1 a0 n }
}

// Auto-scale iters until a timed pass clears ~50 ms, then re-run once at
// the count that lands ON that window, so ns/op is stable even for
// sub-microsecond operations. Caps the ramp so a slow body cannot run
// away.
//
// The ramp alone is not enough to compare two builds. It multiplies by
// 4, so a body whose cost sits near the threshold clears it for one
// build and misses it for the next, and the two results then come from
// runs 4× apart in length — different amounts of warm-up, frequency
// ramp and timer overhead amortised over the ops. Measured on
// `bench/stdlib_hotpath.nu`'s `sort_32_desc`, that reported a 5 %
// REGRESSION for a build that was 8 % faster on both cycle count and
// wall clock. The final calibrated pass removes the dependence on where
// the ramp happened to stop: every reported number comes from a run of
// about `target` nanoseconds.
@ bench_auto s name ( @ v ) body → BenchResult {
    : i target 50000000
    : i cap 100000000
    : ~ i iters 1
    : ~ b done F
    : ~ BenchResult best ( bench_run name 1 body )
    ~ ! done {
        ( bench_result_free best )
        = best ( bench_run name iters body )
        ? | >= ( bench_result_total_ns best ) target >= iters cap {
            = done T
        } {
            = iters * iters 4
        }
    }
    // The clearing pass may have overshot by up to the ramp factor.
    // Scale back onto the target window and measure once more; skip it
    // when the ramp hit its cap (the body is slow enough that the window
    // is already the best available) or when one iteration alone is
    // longer than the target.
    : i total ( bench_result_total_ns best )
    ? & > total target & > iters 1 < iters cap {
        : i want / * iters target total
        ? & > want 0 < want iters {
            ( bench_result_free best )
            = best ( bench_run name want body )
        } {}
    } {}
    ^ best
}

// "name: 12 ns/op  (1000000 iters, 0 allocs/op)"
@ _bench_fmt s name i iters i ns_per_op i allocs_per_op → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out name )
    ( string_push_str out `: ` )
    ( string_push_str out ( nurl_str_int ns_per_op ) )
    ( string_push_str out ` ns/op  (` )
    ( string_push_str out ( nurl_str_int iters ) )
    ( string_push_str out ` iters, ` )
    ( string_push_str out ( nurl_str_int allocs_per_op ) )
    ( string_push_str out ` allocs/op)` )
    ^ out
}

@ bench_report BenchResult r → v {
    : String line ( _bench_fmt ( string_data . r name ) . r iters . r ns_per_op . r allocs_per_op )
    ( nurl_print ( string_data line ) )
    ( nurl_print `\n` )
    ( string_free line )
}
