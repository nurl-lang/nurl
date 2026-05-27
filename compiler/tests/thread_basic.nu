// thread_basic.nu — Phase 5 sanity test: spawn / join / mutex / cond.
//
// Deterministic by construction: every observation happens AFTER the
// joining thread has returned, so there's no scheduler-dependent
// interleaving in the output. Live thread / mutex / cond exercise is
// gated behind NURL_NET_TESTS=1 (same convention as net_loopback.nu /
// http_server_seq.nu) — pthread / Win32 thread spawn is occasionally
// flaky on heavily loaded CI hosts; the gate keeps run_tests.sh's
// default green path deterministic.

$ `stdlib/std/thread.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

: ~ i shared_counter 0
: ~ i ping_flag 0

@ print_kv s label i value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int value ) )
    ( nurl_print `\n` )
}

@ run_live_thread_tests → v {
    // ── Test 1: spawn one thread, join, observe single increment ─
    : Mutex m ( mutex_new )
    : ( @ v ) inc_one \ → v {
        ( mutex_lock m )
        = shared_counter + shared_counter 1
        ( mutex_unlock m )
    }
    : !Thread ThreadErr r1 ( thread_spawn inc_one )
    ?? r1 {
        T t → { ( thread_join t ) }
        F e → { ( nurl_print `T1 spawn failed: ` ) ( nurl_print ( thread_err_name e ) ) ( nurl_print `\n` ) }
    }
    ( print_kv `T1 counter` shared_counter )

    // ── Test 2: 8 threads × 100 increments under the same mutex ─
    = shared_counter 0
    : ( @ v ) inc_loop \ → v {
        : ~ i i 0
        ~ < i 100 {
            ( mutex_lock m )
            = shared_counter + shared_counter 1
            ( mutex_unlock m )
            = i + i 1
        }
    }
    : s thandles ( nurl_alloc 64 )
    : ~ i j 0
    ~ < j 8 {
        : !Thread ThreadErr r ( thread_spawn inc_loop )
        ?? r {
            T t → {
                : s tp . t raw
                : i traw # i tp
                // nurl_poke uses SLOT indexing (×8 stride internally);
                // pass `j`, not `j * 8`.
                ( nurl_poke thandles j traw )
            }
            F e → { ( nurl_print `spawn fail\n` ) }
        }
        = j + j 1
    }
    = j 0
    ~ < j 8 {
        : i traw ( nurl_peek thandles j )
        : s tp # s traw
        : Thread t @ Thread { tp }
        ( thread_join t )
        = j + j 1
    }
    ( nurl_free thandles )
    ( print_kv `T2 counter` shared_counter )

    // ── Test 3: cond_wait / cond_signal handshake ───────────────
    = ping_flag 0
    : Cond c ( cond_new )
    : ( @ v ) producer \ → v {
        ( mutex_lock m )
        = ping_flag 1
        ( cond_signal c )
        ( mutex_unlock m )
    }
    : !Thread ThreadErr r3 ( thread_spawn producer )
    ?? r3 {
        T t → {
            ( mutex_lock m )
            ~ == ping_flag 0 { ( cond_wait c m ) }
            ( mutex_unlock m )
            ( thread_join t )
        }
        F e → { ( nurl_print `T3 spawn failed\n` ) }
    }
    ( print_kv `T3 flag` ping_flag )

    ( cond_free c )
    ( mutex_free m )
}

@ main → i {
    // ThreadErr name table — sanity check, exercised unconditionally so
    // a tag renumber blows the test up at link-comparison time even when
    // NURL_NET_TESTS is off.
    ( nurl_print `thread_err_name(ThreadCreate)=` )
    ( nurl_print ( thread_err_name # ThreadErr ThreadCreate ) )
    ( nurl_print `\n` )
    ( nurl_print `thread_err_name(ThreadOther)=` )
    ( nurl_print ( thread_err_name # ThreadErr ThreadOther ) )
    ( nurl_print `\n` )

    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_live_thread_tests )
        }
        F → { ( nurl_print `live thread tests skipped (set NURL_NET_TESTS=1 to enable)\n` ) }
    }
    ^ 0
}
