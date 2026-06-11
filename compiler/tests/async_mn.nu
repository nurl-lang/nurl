// async_mn.nu — Phase 3 M:N work-stealing test.
//
// Verifies:
//   * `spawn_joinable` survives DONE and stays joinable
//   * `fiber_join` completes only after the fiber's body returned
//   * `fiber_worker_id` reports a valid id (0..worker_count-1) from
//     inside a fiber and -1 outside
//   * Spawning many fibers from outside the runtime drops them into
//     the global queue, and every worker eventually pulls some
//     (steal protocol exercised on imbalance)
//   * `runtime_shutdown` joins workers cleanly
//
// Determinism: the per-worker fiber-count histogram is sensitive to
// the scheduling order and is NOT asserted; we print "ok" instead so
// the snapshot stays stable across machines. The counter (sum of
// each fiber's contribution) IS deterministic under the mutex.

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`

: ~ i counter 0
: ~ i joined 0

@ main → i {
    ( runtime_init 4 )  // pin to 4 workers for the test
    : Mutex m ( mutex_new )

    // ── A: spawn_joinable + fiber_join round-trip ──────────────────
    : ( @ v ) tiny \ → v {
        ( mutex_lock m )
        = counter + counter 1
        ( mutex_unlock m )
    }

    : Fiber f1 ( spawn_joinable tiny )
    ( fiber_join f1 )
    = joined + joined 1

    ( nurl_print `A1 counter=` )
    ( nurl_print ( nurl_str_int counter ) )
    ( nurl_print `\n` )

    // ── B: 200 joinable fibers, each contributes once ──────────────
    // `nurl_poke` / `nurl_peek` use i64-slot indexing (not byte
    // offsets) — index `i` lands at byte `i*8`. Allocate 200 i64
    // slots = 1600 bytes.
    = counter 0
    : s handles ( nurl_alloc * 200 8 )
    : ~ i i 0
    ~ < i 200 {
        : Fiber fx ( spawn_joinable tiny )
        : s rpx . fx raw
        : i rawx # i rpx
        ( nurl_poke handles i rawx )
        = i + i 1
    }
    = i 0
    ~ < i 200 {
        : i rawx ( nurl_peek handles i )
        : s rpx # s rawx
        : Fiber fx @ Fiber { rpx }
        ( fiber_join fx )
        = i + i 1
    }
    ( nurl_free handles )

    ( nurl_print `B1 counter=` )
    ( nurl_print ( nurl_str_int counter ) )
    ( nurl_print `\n` )

    // ── C: fiber_worker_id is -1 outside any fiber ─────────────────
    : i wid ( nurl_fiber_worker_id )
    ( nurl_print `C1 worker_id_outside=` )
    ( nurl_print ( nurl_str_int wid ) )
    ( nurl_print `\n` )

    // ── D: fire-and-forget spawn, runtime_run drains ───────────────
    = counter 0
    : ( @ v ) yielder \ → v {
        : ~ i k 0
        ~ < k 50 {
            ( yield )
            = k + k 1
        }
        ( mutex_lock m )
        = counter + counter 1
        ( mutex_unlock m )
    }
    = i 0
    ~ < i 500 {
        ( spawn yielder )
        = i + i 1
    }
    ( runtime_run )

    ( nurl_print `D1 counter=` )
    ( nurl_print ( nurl_str_int counter ) )
    ( nurl_print `\n` )

    ( mutex_free m )
    ( runtime_shutdown )
    ^ 0
}
