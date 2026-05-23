// arc_threads.nu — Arc[T] across thread boundaries.
//
// Spawns 8 threads that each arc_clone the same handle, do some
// work, and arc_free their clone. The expectation: the original
// arc_strong walks back to 1 after all workers exit, then to 0
// after the main thread's final arc_free, releasing the storage.
//
// Same `NURL_NET_TESTS=1` gate as thread_basic — pthread spawn is
// occasionally flaky on heavily loaded CI hosts; the gate keeps the
// default green path deterministic.

$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

// Module-level: every worker captures and clones this Arc handle.
// `i ` rather than `String` to keep the value side trivial — we are
// stress-testing the refcount, not the payload.
: ~ i shared_ctl 0

@ run_live_arc_tests → v {
    : ( Arc i ) base ( arc_new [i] 42 )
    = shared_ctl # i . base ctl

    : Mutex print_lock ( mutex_new )

    // Worker: clone, observe, free. No mutation — we are testing
    // that the refcount churn under contention stays balanced.
    : ( @ v ) worker \ → v {
        : s rp # s shared_ctl
        : ( Arc i ) my @ ( Arc i ) { rp }
        : ( Arc i ) cl ( arc_clone [i] my )
        // touch the value (read race; safe because nobody writes)
        : i v ( arc_get [i] cl )
        ( mutex_lock print_lock )
        ( nurl_print `worker saw value=` )
        ( nurl_print ( nurl_str_int v ) )
        ( nurl_print `\n` )
        ( mutex_unlock print_lock )
        ( arc_free [i] cl )
    }

    // Spawn 8 workers. `nurl_peek` / `_poke` index by i64 slot, so
    // an 8-slot table is 64 bytes; the slot index is `j` itself, not
    // `j * 8` (that subtle aliasing trap is documented in §9 of the
    // runtime — pass element indices, not byte offsets).
    : s thandles ( nurl_alloc 64 )
    : ~ i j 0
    ~ < j 8 {
        : !Thread ThreadErr r ( thread_spawn worker )
        ?? r {
            T t → {
                : s tp . t raw
                : i traw # i tp
                ( nurl_poke thandles j traw )
            }
            F e → { ( nurl_print `spawn fail\n` ) }
        }
        = j + j 1
    }

    // Join all.
    = j 0
    ~ < j 8 {
        : i traw ( nurl_peek thandles j )
        : s tp # s traw
        : Thread t @ Thread { tp }
        ( thread_join t )
        = j + j 1
    }
    ( nurl_free thandles )

    // After every worker has arc_free'd its clone, only `base`
    // remains. count should be exactly 1.
    ( nurl_print `final count=` ) ( nurl_print ( nurl_str_int ( arc_strong [i] base ) ) )
    ( nurl_print `\n` )

    ( arc_free [i] base )
    ( mutex_free print_lock )
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_live_arc_tests )
        }
        F → { ( nurl_print `live arc thread tests skipped (set NURL_NET_TESTS=1 to enable)\n` ) }
    }
    ^ 0
}
