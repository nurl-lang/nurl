// semaphore_basic.nu — regression for the counting Semaphore added to
// stdlib/std/thread.nu (sem_new / acquire / try_acquire / release /
// avail / free).
//
// The counting logic is checked deterministically and single-threaded via
// sem_try_acquire (no scheduler dependence). A live multi-threaded
// exercise — N threads bounded by a sem(K), asserting the observed peak
// concurrency never exceeds K — is gated behind NURL_NET_TESTS=1, the
// same convention thread_basic.nu uses (thread spawn is occasionally
// flaky on loaded CI hosts; the default path stays deterministic).
//
// main returns the number of failed checks (0 = all pass).

$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

// Shared state for the live concurrency test (module-level mutables, the
// pattern thread_basic.nu uses for closure-captured counters).
: ~ i live_active 0
: ~ i live_peak 0

@ chk b cond s tag → i {
    ? cond {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ run_live_test i n_threads i permits Mutex guard Semaphore gate → v {
    : ( @ v ) worker \ → v {
        : ~ i it 0
        ~ < it 50 {
            ( sem_acquire gate )
            // Enter the bounded region: bump active + track the peak.
            ( mutex_lock guard )
            = live_active + live_active 1
            ? > live_active live_peak { = live_peak live_active } {}
            ( mutex_unlock guard )
            // Spin a little so overlap is likely (keeps the region busy).
            : ~ i spin 0
            ~ < spin 2000 { = spin + spin 1 }
            // Leave the bounded region.
            ( mutex_lock guard )
            = live_active - live_active 1
            ( mutex_unlock guard )
            ( sem_release gate )
            = it + it 1
        }
    }
    : s thandles ( nurl_alloc * n_threads 8 )
    : ~ i j 0
    ~ < j n_threads {
        : !Thread ThreadErr r ( thread_spawn worker )
        ?? r {
            T t → { ( nurl_poke thandles j # i . t raw ) }
            F _ → { ( nurl_poke thandles j 0 ) }
        }
        = j + j 1
    }
    = j 0
    ~ < j n_threads {
        : i traw ( nurl_peek thandles j )
        ? != traw 0 { ( thread_join @ Thread { # s traw } ) } {}
        = j + j 1
    }
    ( nurl_free thandles )
}

@ main → i {
    : ~ i f 0

    // ── Deterministic counting via try_acquire (no threads) ──
    : Semaphore s ( sem_new 2 )
    = f + f ( chk == ( sem_avail s ) 2 `avail_initial_2` )
    = f + f ( chk ( sem_try_acquire s ) `try1_ok` )  // 2 → 1
    = f + f ( chk ( sem_try_acquire s ) `try2_ok` )  // 1 → 0
    = f + f ( chk == ( sem_avail s ) 0 `avail_zero` )
    = f + f ( chk ! ( sem_try_acquire s ) `try3_blocked` )  // 0 → fail
    ( sem_release s )  // 0 → 1
    = f + f ( chk == ( sem_avail s ) 1 `avail_after_release` )
    = f + f ( chk ( sem_try_acquire s ) `try4_ok` )  // 1 → 0
    = f + f ( chk ! ( sem_try_acquire s ) `try5_blocked` )
    ( sem_release s )
    ( sem_release s )
    = f + f ( chk == ( sem_avail s ) 2 `avail_restored` )
    ( sem_free s )

    // sem_new clamps a non-positive count to 0 (never negative permits).
    : Semaphore z ( sem_new - 0 3 )
    = f + f ( chk == ( sem_avail z ) 0 `neg_clamped_to_0` )
    = f + f ( chk ! ( sem_try_acquire z ) `neg_no_permit` )
    ( sem_free z )

    // ── Live concurrency bound (gated) ──
    : ?String gate_env ( env_get `NURL_NET_TESTS` )
    ?? gate_env {
        T g → {
            ( string_free g )
            : i permits 3
            : Mutex guard ( mutex_new )
            : Semaphore gate ( sem_new permits )
            = live_active 0
            = live_peak 0
            ( run_live_test 8 permits guard gate )
            // The hard invariant: peak concurrency never exceeded the
            // permit count, and the region was actually entered.
            = f + f ( chk <= live_peak permits `live_peak_within_bound` )
            = f + f ( chk >= live_peak 1 `live_region_entered` )
            ( sem_free gate )
            ( mutex_free guard )
        }
        F _ → {
            ( nurl_print `live_concurrency skipped (set NURL_NET_TESTS=1)\n` )
        }
    }

    ^ f
}
