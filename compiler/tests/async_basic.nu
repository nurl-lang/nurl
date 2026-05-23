// async_basic.nu — Phase 1/2/3 stackful-fiber smoke test (M:N).
//
// Spawn 100 fibers, each yielding 1000 times. The M:N work-stealing
// scheduler (default workers = sysconf(_SC_NPROCESSORS_ONLN); override
// with NURL_WORKERS env) should drain all 100 000 yields and let every
// fiber finish. Verifies:
//   * ucontext-based context switch works
//   * mmap'd 64 KB stacks + guard page are reachable & releasable
//   * fair scheduling — every spawned fiber eventually gets every
//     yield slice
//   * `runtime_run` returns when pending fiber count reaches zero
//   * closures captured by N spawned fibers share their env correctly
//   * Mutex from §19 composes with §24's fibers — the counter
//     increments are protected
//   * `runtime_shutdown` joins every worker cleanly
//
// POSIX-only at v1: on WASI / Windows the FFI returns failure and
// total_yields / finished print 0.

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/string.nu`

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
    ( runtime_shutdown )
    ^ 0
}
