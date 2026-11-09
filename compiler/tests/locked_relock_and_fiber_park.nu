// locked_relock_and_fiber_park.nu — a Locked's lock is a check-out with a
// holder (stdlib/runtime_locked.c, agora #455).
//
// 1. A locked_* call nested in another one's closure on the SAME Locked
//    panics, naming the call. It relocked the pthread mutex the thread
//    held: undefined by POSIX, a hang on glibc, and on FreeBSD (whose
//    default mutex is the error-checking one) the inner closure ran on
//    the value the outer one was still using. Recovered, the lock is the
//    holder's still, so after the outer call returns the Locked works on.
// 2. ONE worker. A fiber parks (a sleep) inside locked_update's closure,
//    holding the Locked in place; another fiber on the same worker asks
//    for it. The closure used to run with the OS mutex held, so the
//    second fiber's lock stopped the worker and the holder never resumed
//    (a hang). Now the second fiber parks until the value is let go.
// 3. A value taken (locked_take) and handed to another thread, which
//    restores it, while the taker waits in locked_get: a check-out has no
//    holder, so that wait is no self-wait.
// 4. locked_await wakes on a change made through locked_with's view.
// requires: live fibers

$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/panic.nu`

@ __park_inside ( Locked i ) l → v {
    ( locked_update [i] l \ inout i x → v {
        : i was x
        ( sleep_ms 2 )
        = x + was 1
    } )
}

@ main → i {
    // 1. A nested call on the same Locked.
    : ( Locked ( Vec i ) ) q ( locked_new [( Vec i )] ( vec_new [i] ) )
    : ( Locked ( Vec i ) ) q2 ( Locked_share [( Vec i )] q )
    ( locked_with [( Vec i )] q \ ( Vec i ) xs → v {
        ( vec_push [i] xs 7 )
        : !v PanicInfo pr ( recover \ → v {
            ( locked_with [( Vec i )] q2 \ ( Vec i ) ys → v { ( vec_clear [i] ys ) } )
        } )
        ?? pr {
            T _ → { ( nurl_println `nested: no panic` ) }
            F p → { ( nurl_print `nested: ` ) ( nurl_println ( string_data . p msg ) ) }
        }
        ( vec_push [i] xs 8 )
    } )
    ( nurl_print `after nested, len=` )
    ( nurl_println_int ( vec_len [i] ( locked_get [( Vec i )] q ) ) )

    // 2. Two fibers, one worker, the holder parked in place.
    ( runtime_init 1 )
    : ( Locked i ) l ( locked_new [i] 0 )
    : ( Locked i ) la ( Locked_share [i] l )
    : ( Locked i ) lb ( Locked_share [i] l )
    : ( @ v ) fa \ → v { : ~ i k 0 ~ < k 5 { ( __park_inside la ) = k + k 1 } }
    : ( @ v ) fb \ → v { : ~ i k 0 ~ < k 5 { ( __park_inside lb ) = k + k 1 } }
    ( spawn fa )
    ( spawn fb )
    ( runtime_run )
    ( runtime_shutdown )
    ( nurl_print `two_fibers_parked_in_place=` )
    ( nurl_println_int ( locked_get [i] l ) )

    // 3. Taken here, restored by another thread.
    : ( Locked i ) m ( locked_new [i] 40 )
    : ( Locked i ) mt ( Locked_share [i] m )
    : ( Channel i ) ch ( chan_new [i] )
    : ( Channel i ) cht ( Channel_share [i] ch )
    : ~ i x ( locked_take [i] m )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        ?? ( chan_recv [i] cht ) { T y → { ( locked_restore [i] mt + y 2 ) } F → {} }
    } )
    ( chan_send [i] ch x )
    ( nurl_print `restored_by_another_thread=` )
    ( nurl_println_int ( locked_get [i] m ) )
    ?? t { T th → { : i _j ( thread_join th ) } F _ → {} }

    // 4. An awaiter woken by a change through locked_with.
    : ( Locked ( Vec i ) ) w ( locked_new [( Vec i )] ( vec_new [i] ) )
    : ( Locked ( Vec i ) ) ww ( Locked_share [( Vec i )] w )
    : !Thread ThreadErr t2 ( thread_spawn \ → v {
        ( sleep_ms 5 )
        ( locked_with [( Vec i )] ww \ ( Vec i ) xs → v { ( vec_push [i] xs 99 ) } )
    } )
    : i got ( locked_await [( Vec i ) i] w \ inout ( Vec i ) xs → ?i {
        ? > ( vec_len [i] xs ) 0 { ^ @ ?i { T ( vec_at [i] xs 0 ) } } {}
        ^ @ ?i { F 0 }
    } )
    ( nurl_print `await_woken_by_with=` )
    ( nurl_println_int got )
    ?? t2 { T th → { : i _j ( thread_join th ) } F _ → {} }
    ^ 0
}
