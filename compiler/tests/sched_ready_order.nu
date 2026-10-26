// sched_ready_order.nu — on a saturated worker, fibers whose I/O became
// ready run in the order it became ready (agora #113).
//
// ONE worker. N readers park on their own socketpair; Y yielders keep
// the worker's run queue from ever emptying; a writer makes reader i's
// socket readable in order i, one per dispatch of its own. Each reader
// records how far its completion rank is from its arrival index.
//
// The rule: a fiber the netpoller wakes joins the TAIL of the order of
// runnable fibers (it runs at once only on an idle worker), local and
// global queues are served oldest first, and the netpoller is polled
// every 16th dispatch whatever is queued. A poll window then holds at
// most 16 arrivals, so a reader can be overtaken only within its own
// window: the displacement stays below 16, whatever N, Y and timing.
//
// Before, a poll's first fiber ran at once and its next eight went to
// the worker's local queue, ahead of older readers spilled to the
// global queue; with a busy local queue the poller ran only every
// 128th dispatch and the global queue was served only when it found
// nothing. A reader spilled early ran after nearly every later one.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/unixsock.nu`
$ `stdlib/core/vec.nu`

: ~ i ranks 0
: ~ i max_disp 0
: ~ i woke_ready 0

@ __reader i idx i fd → v {
    : i rc ( wait_readable fd - 0 1 )
    ? == rc 1 { = woke_ready + woke_ready 1 } {}
    : i r ranks
    = ranks + ranks 1
    : i d ? > r idx - r idx - idx r
    ? > d max_disp { = max_disp d } {}
}

@ __yielder i n → v {
    : ~ i k 0
    ~ < k n {
        ( yield )
        = k + k 1
    }
}

@ __writer ( Vec i ) wfds → v {
    : ~ i i 0
    ~ < i ( vec_len [i] wfds ) {
        ?? ( vec_get [i] wfds i ) {
            T fd → { : !v UnixErr w ( unix_write_str @ UnixConn { fd } `x` ) }
            F → {}
        }
        ( yield )
        = i + i 1
    }
}

@ main → i {
    : i n 200
    : i y 7
    ( runtime_init 1 )
    : ( Vec i ) wfds ( vec_new [i] )
    : ~ i i 0
    ~ < i n {
        : !UnixPair UnixErr pr ( unix_socketpair )
        ?? pr {
            T p → {
                ( vec_push [i] wfds . . p a fd )
                : i rfd . . p b fd
                : i idx i
                ( spawn_owned \ → v { ( __reader idx rfd ) } )
            }
            F _ → { ( nurl_print `socketpair failed\n` ) ^ 1 }
        }
        = i + i 1
    }
    = i 0
    ~ < i y {
        ( spawn_owned \ → v { ( __yielder 20000 ) } )
        = i + i 1
    }
    ( spawn_owned \ → v { ( __writer wfds ) } )
    ( runtime_run )
    ( runtime_shutdown )
    ( nurl_print `readers=` )
    ( nurl_println_int ranks )
    ( nurl_print `woke_ready=` )
    ( nurl_println_int woke_ready )
    ( nurl_print `displacement_below_16=` )
    ( nurl_print ? < max_disp 16 `yes` `no` )
    ( nurl_print `\n` )
    ? >= max_disp 16 {
        ( nurl_print `max_displacement=` )
        ( nurl_println_int max_disp )
    } {}
    ^ 0
}
