// fiber_sleep_timer_not_lost.nu — a fiber's sleep is woken on time however
// its timer and the netpoller's own sleep interleave (agora #538).
//
// FOUR workers, eight fibers. Each takes a Locked's value out, now and
// then sleeps a millisecond while it is out, and puts it back one higher;
// the others wait on the Locked meanwhile, so the workers keep going idle
// and the poller keeps going to sleep. The poller read the earliest
// deadline under its lock, let the lock go, and only then said it was
// asleep, and until when. A sleep armed in between found it awake, poked
// nobody, and the poller slept in epoll_wait(-1) past the timer: the
// sleeper never woke, and the seven waiting on what it held waited with it
// (about 13 runs in 100 of one round hung on main; this runs thirty rounds, about 3 s).
// Work queued in that same window was slept through the same way.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ __round → i {
    ( runtime_init 4 )
    : ( Locked i ) l ( locked_new [i] 0 )
    : ~ i f 0
    ~ < f 8 {
        : ( Locked i ) lf ( Locked_share [i] l )
        : i me f
        ( spawn \ → v {
            : ~ i k 0
            ~ < k 8000 {
                : ~ i x ( locked_take [i] lf )
                ? == 0 % + k me 199 { ( sleep_ms 1 ) } {}
                = x + x 1
                ( locked_restore [i] lf x )
                = k + k 1
            }
        } )
        = f + f 1
    }
    ( runtime_run )
    ( runtime_shutdown )
    ^ ( locked_get [i] l )
}

@ main → i {
    : ~ i r 0
    : ~ i ok 0
    ~ < r 30 { ? == ( __round ) 64000 { = ok + ok 1 } {} = r + r 1 }
    ( nurl_print `rounds finished whole: ` )
    ( nurl_println_int ok )
    ^ 0
}
