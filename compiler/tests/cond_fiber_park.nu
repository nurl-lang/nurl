// cond_fiber_park.nu — a fiber that waits on a Cond parks; it does not
// stop its worker thread (agora #255).
//
// ONE worker. A fiber takes a Locked's value out (locked_take) and parks
// while it holds it (a sleep). Another fiber on the same worker wants the
// value too and waits for it to come back. That wait was a pthread
// cond_wait: it stopped the worker thread, the holder could never resume
// to put the value back, and the program hung forever. Now the waiter
// parks and the worker runs the holder on. The same for a Semaphore with
// one permit held across a park, and for a Locked a THREAD and a fiber
// take turns on — one Cond serves both kinds of waiter.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

// Take the value out, park while holding it, put it back one higher.
@ __bump ( Locked i ) l i ms → v {
    : ~ i x ( locked_take [i] l )
    ( sleep_ms ms )
    = x + x 1
    ( locked_restore [i] l x )
}

// Hold the only permit across a park.
@ __gate Semaphore s ( Locked i ) n → v {
    ( sem_acquire s )
    ( sleep_ms 1 )
    ( locked_update [i] n \ inout i x → v { = x + x 1 } )
    ( sem_release s )
}

@ main → i {
    ( runtime_init 1 )

    : ( Locked i ) l ( locked_new [i] 0 )
    : ( Locked i ) la ( Locked_share [i] l )
    : ( Locked i ) lb ( Locked_share [i] l )
    : ( @ v ) fa \ → v { : ~ i k 0 ~ < k 5 { ( __bump la 2 ) = k + k 1 } }
    : ( @ v ) fb \ → v { : ~ i k 0 ~ < k 5 { ( __bump lb 1 ) = k + k 1 } }
    ( spawn fa )
    ( spawn fb )

    : Semaphore s ( sem_new 1 )
    : Semaphore sa ( Semaphore_share s )
    : Semaphore sb ( Semaphore_share s )
    : ( Locked i ) n ( locked_new [i] 0 )
    : ( Locked i ) na ( Locked_share [i] n )
    : ( Locked i ) nb ( Locked_share [i] n )
    : ( @ v ) ga \ → v { : ~ i k 0 ~ < k 5 { ( __gate sa na ) = k + k 1 } }
    : ( @ v ) gb \ → v { : ~ i k 0 ~ < k 5 { ( __gate sb nb ) = k + k 1 } }
    ( spawn ga )
    ( spawn gb )

    : ( Locked i ) m ( locked_new [i] 0 )
    : ( Locked i ) mt ( Locked_share [i] m )
    : ( Locked i ) mf ( Locked_share [i] m )
    : ( @ v ) tbody \ → v {
        : ~ i k 0
        ~ < k 5 {
            : ~ i x ( locked_take [i] mt )
            ( sleep_ms 1 )
            = x + x 1
            ( locked_restore [i] mt x )
            = k + k 1
        }
    }
    : ( @ v ) fm \ → v { : ~ i k 0 ~ < k 5 { ( __bump mf 1 ) = k + k 1 } }
    : !Thread ThreadErr t ( thread_spawn tbody )
    ( spawn fm )

    ( runtime_run )
    ?? t { T th → { : i _j ( thread_join th ) } F _ → {} }
    ( runtime_shutdown )

    ( nurl_print `two_fibers_one_locked=` )
    ( nurl_println_int ( locked_get [i] l ) )
    ( nurl_print `two_fibers_one_permit=` )
    ( nurl_println_int ( locked_get [i] n ) )
    ( nurl_print `thread_and_fiber_one_locked=` )
    ( nurl_println_int ( locked_get [i] m ) )
    ^ 0
}
