// async_sleep.nu — Phase 5 I/O reactor timer test.
//
// Spawn 10 fibers, each `sleep_ms(50)`. All 10 sleep concurrently —
// the wall time should be ~50ms total, not 500ms — because the
// reactor parks them on its timer wheel and the workers stay free.
// Verifies:
//   * sleep_ms parks the calling fiber (worker not blocked)
//   * Reactor wakes the fiber when the deadline elapses
//   * Multiple concurrent sleeps share the same reactor without
//     serialization
//   * Total wall time is dominated by the longest sleep, not their
//     sum
//
// We assert the count of completions (deterministic) and print a
// boolean for the wall-time bound (deterministic on any machine
// that can run a poll-based reactor faster than 250ms per timer).

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/time.nu`

: ~ i done_count 0

@ main → i {
    ( runtime_init 4 )
    : Mutex m ( mutex_new )

    : ( @ v ) sleeper \ → v {
        ( sleep_ms 50 )
        ( mutex_lock m )
        = done_count + done_count 1
        ( mutex_unlock m )
    }

    : i t0 ( now_ms )
    : ~ i n 0
    ~ < n 10 {
        ( spawn sleeper )
        = n + n 1
    }
    ( runtime_run )
    : i t1 ( now_ms )
    : i elapsed - t1 t0

    ( nurl_print `done=` )
    ( nurl_print ( nurl_str_int done_count ) )
    ( nurl_print `\n` )
    // Wall time should be 50ms ± scheduling jitter. We assert <250ms
    // (5× slack); anything more would mean the sleeps are serializing
    // through the worker pool instead of parking on the reactor.
    ( nurl_print `parallel=` )
    ( nurl_print ? < elapsed 250 `yes` `no` )
    ( nurl_print `\n` )

    ( mutex_free m )
    ( runtime_shutdown )
    ^ 0
}
