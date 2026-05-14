// Test: stdlib/std/time.nu
//
// Time output is intrinsically non-deterministic, so we verify only
// invariants that can be expressed as true/false:
//
//   - now_ms / now_seconds / monotonic_ns return positive 64-bit values
//   - now_seconds * 1000 ≈ now_ms (within 5 s of skew tolerance)
//   - monotonic_ns is non-decreasing across two reads
//   - sleep_ms 50 advances the monotonic clock by ≥ 30 ms
//                                                  (safe lower bound — host
//                                                   schedulers can be slow)

$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`

@ pb b v s label → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ? v `T` `F` ) ( nurl_print `\n` )
}

@ main → i {
    // ── Wall-clock plausibility ───────────────────────────
    : i ms ( now_ms )
    : i sec ( now_seconds )
    : i mono ( monotonic_ns )

    ( pb > ms 0 `now_ms_positive` )
    ( pb > sec 0 `now_seconds_positive` )
    ( pb > mono 0 `monotonic_ns_positive` )

    // sec * 1000 should be within 5s of ms (covers the boundary where
    // ms and sec straddle a second tick).
    : i diff - ms * sec 1000
    ? < diff 0 { = diff - 0 diff } {}
    ( pb < diff 5000 `now_ms_seconds_consistent` )

    // ── Monotonic ordering ────────────────────────────────
    : i a ( monotonic_ns )
    : i b ( monotonic_ns )
    ( pb >= b a `monotonic_non_decreasing` )

    // ── sleep_ms ───────────────────────────────────────────
    : i t0 ( monotonic_ns )
    ( sleep_ms 50 )
    : i ms_elapsed ( elapsed_ms_since t0 )
    ( pb >= ms_elapsed 30 `slept_at_least_30ms` )
    // and not absurdly long (e.g. a frozen test would catch on wall-clock)
    ( pb <= ms_elapsed 5000 `slept_under_5s` )

    // sleep_ms with non-positive values is a no-op
    : i t1 ( monotonic_ns )
    ( sleep_ms 0 )
    ( sleep_ms -100 )
    : i fast ( elapsed_ms_since t1 )
    ( pb < fast 100 `nonpositive_sleep_no_op` )

    ( nurl_print `done\n` )
    ^ 0
}
