// async_basic.nu — Phase 1/2/3 stackful-fiber smoke test (M:N).
//
// Spawn 100 fibers, each yielding 1000 times. The M:N work-stealing
// scheduler (default workers = sysconf(_SC_NPROCESSORS_ONLN); override
// with NURL_WORKERS env) should drain all 100 000 yields and let every
// fiber finish. Verifies:
//   * the stackful context switch works (runtime_ctx.c where it
//     exists, ucontext elsewhere)
//   * mmap'd 64 KB stacks + guard page are reachable & releasable
//   * fair scheduling — every spawned fiber eventually gets every
//     yield slice
//   * `runtime_run` returns when pending fiber count reaches zero
//   * closures captured by N spawned fibers share their env correctly
//   * Mutex from §19 composes with §24's fibers — the counter
//     increments are protected
//   * `runtime_shutdown` joins every worker cleanly
//
// On a platform with no fiber backend (WASI / Windows) the FFI
// returns failure, the closures never run, and total_yields / finished
// print 0 — see docs/ASYNC.md §5 on why that is a silent wrong answer
// rather than a degraded one.

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`

: ~ i total_yields 0
: ~ i finished 0

@ main → i {
    ( runtime_init 0 )
    : Mutex m ( mutex_new )

    : ( @ v ) work \ → v {
        : ~ i k 0
        ~ < k 1000 {
            ( yield )
            ( mutex_lock m )
            = total_yields + total_yields 1
            ( mutex_unlock m )
            = k + k 1
        }
        ( mutex_lock m )
        = finished + finished 1
        ( mutex_unlock m )
    }

    : ~ i n 0
    ~ < n 100 {
        ( spawn work )
        = n + n 1
    }
    ( runtime_run )

    ( nurl_print `total_yields=` )
    ( nurl_print ( nurl_str_int total_yields ) )
    ( nurl_print `\n` )
    ( nurl_print `finished=` )
    ( nurl_print ( nurl_str_int finished ) )
    ( nurl_print `\n` )

    ( mutex_free m )
    // `spawn` decomposes the closure, so the env escaped and is ours to
    // release (docs/MEMORY.md §7.4). Safe here and only here: runtime_run
    // has returned, so every fiber that could still be reading it is done.
    ( nurl_free # s # *u work 1 )
    ( runtime_shutdown )
    ^ 0
}
