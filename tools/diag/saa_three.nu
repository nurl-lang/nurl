// sched_accept_admission.nu — on a saturated worker, a connection is
// accepted within one poll window of arriving (agora #113).
//
// ONE worker. Y yielders keep its run queue from ever emptying; each
// dispatch of one does ~20 µs of work and counts itself in `ticks`. An
// acceptor fiber accepts on a loopback listener; a client THREAD — the
// outside world — connects N times, one at a time, and notes `ticks`
// when each connection ARRIVES: when it waits in the listener's accept
// queue (tcp_listener_pending), or the acceptor has already taken it.
// The acceptor notes `ticks` as each accept returns. A connection's
// admission delay is the yielder dispatches between the two.
//
// Arrival is not the client's connect() returning. On Linux the two are
// one moment: the loopback handshake runs inside the client's syscall.
// On macOS the server side completes in a later kernel step, and with
// every CPU busy that step runs only at a scheduling point of the busy
// thread: here, the worker's kevent, every 16th dispatch. Stamped at
// connect(), a connection then looked 32 and 48 dispatches late on the
// macOS CI runner, where the runtime had run the acceptor at the first
// poll that saw it (agora #500; a C program with no NURL runtime, polling
// every 16th 20 µs unit, measured the same steps).
//
// The rule (Admission, stdlib/runtime_ffi.c "Service order"): a fiber
// parked in an accept runs as soon as its listener is polled ready,
// ahead of everything queued. The netpoller (Linux, macOS, FreeBSD,
// Windows) is polled every 16th dispatch, so the delay stays within 16,
// and the unikernel's socket layer (nolibc, where the client thread is a
// coroutine too) wakes it to the head of the bare runtime's run queue.
// Either way the delay is far below Y, whatever N and timing. Skipped
// where a reactor THREAD polls instead (the poll(2) fallback): it puts
// the acceptor at the head of the run queue only once the OS gives that
// thread a time slice, which on a loaded host is tens of milliseconds
// (agora #137; test_skips.sh).
//
// Before, the acceptor joined the TAIL of the run queue like any woken
// fiber and waited behind all Y yielders first: a delay of at least Y
// on every connection. The connections it then spawned were stamped
// after everything that had become runnable meanwhile — on a saturated
// TLS server a connection waited one pass of the run queue in the
// kernel's queue and another in the run queue, and tls-bench's
// handshake latency spread over twice the rustls range.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __port TcpListener l → i {
    : String address ( tcp_local_addr l )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ^ port
}

@ __yielder Atomic ticks Atomic done → v {
    ~ == ( atomic_load done ) 0 {
        : i t0 ( monotonic_ns )
        ~ < - ( monotonic_ns ) t0 20000 {}
        : i _t ( atomic_add ticks 1 )
        ( yield )
    }
}

@ __acceptor TcpListener l i n Atomic ticks Atomic taken Atomic done ( Channel i ) acc → v {
    : ~ i k 0
    ~ < k n {
        ?? ( tcp_accept_transport l ) {
            T c → {
                : b _s ( chan_send [i] acc ( atomic_load ticks ) )
                : i _k ( atomic_add taken 1 )
                ( tcp_close_conn c )
                = k + k 1
            }
            F _ → { = k n }
        }
    }
    ( atomic_store done 1 )
}

@ main → i {
    : i n 100
    : i y 64
    ( runtime_init 1 )
    : TcpListener l ?? ( tcp_listen `127.0.0.1` 0 ) { T x → x F _ → { ( nurl_print `listen failed\n` ) ^ 1 } }
    : i port ( __port l )
    : Atomic ticks ( atomic_new 0 )
    : Atomic done ( atomic_new 0 )
    : Atomic taken ( atomic_new 0 )
    : ( Channel i ) acc ( chan_new [i] )
    // The acceptor first: it parks in its accept before the yielders
    // fill the queue, so every connection meets it parked.
    ( spawn_owned \ → v { ( __acceptor l n ticks taken done acc ) } )
    : ~ i i 0
    ~ < i y {
        ( spawn_owned \ → v { ( __yielder ticks done ) } )
        = i + i 1
    }
    // The outside world: connect, note the tick the connection arrives
    // at, close, let the server get busy again. Arrived: it waits in the
    // listener's queue, or the acceptor took it already (a delay of 0).
    // A listener that cannot be asked (-1) leaves connect()'s return.
    : Atomic ct ( Atomic_share ticks )
    : Atomic ctaken ( Atomic_share taken )
    : TcpListener cl ( TcpListener_share l )
    : ( Channel i ) cv ( chan_new [i] )
    : ( Channel i ) cv0 ( chan_new [i] )
    : !Thread ThreadErr client ( thread_spawn \ → v {
        : ~ i j 0
        ~ < j n {
            ?? ( tcp_connect `127.0.0.1` port ) {
                T c → {
                    : b _s0 ( chan_send [i] cv0 ( atomic_load ct ) )
                    : ~ b here F
                    ~ ! here {
                        ? > ( atomic_load ctaken ) j { = here T } {
                            ? != ( tcp_listener_pending cl 1 ) 0 { = here T } {}
                        }
                    }
                    : b _s ( chan_send [i] cv ( atomic_load ct ) )
                    ( tcp_close_conn c )
                }
                F _ → { : b _s ( chan_send [i] cv -1 ) : b _s0 ( chan_send [i] cv0 -1 ) }
            }
            ( sleep_ms 1 )
            = j + j 1
        }
    } )
    ( runtime_run )
    ?? client { T t → { : i _j ( thread_join t ) } F _ → {} }
    ( runtime_shutdown )
    ( tcp_close_listener l )
    : ~ i worst0 0
    : ~ i worst 0
    : ~ i bad 0
    : ~ i got 0
    : ~ b more T
    ~ more {
        ?? ( chan_try_recv [i] acc ) {
            T a → {
                : i c ?? ( chan_try_recv [i] cv ) { T x → x F → -1 }
                : i c0 ?? ( chan_try_recv [i] cv0 ) { T x → x F → -1 }
                ? >= c0 0 { : i d0 ? > a c0 - a c0 0 ? > d0 worst0 { = worst0 d0 } {} } {}
                ? < c 0 { = bad + bad 1 } {
                    : i d ? > a c - a c 0
                    ? > d worst { = worst d } {}
                }
                = got + got 1
            }
            F → { = more F }
        }
    }
    ( nurl_print `w_connect=` )
    ( nurl_println_int worst0 )
    ( nurl_print `w_arrival=` )
    ( nurl_println_int worst )
    ( nurl_print `accepted=` )
    ( nurl_println_int got )
    ( nurl_print `connect_failures=` )
    ( nurl_println_int bad )
    ( nurl_print `admitted_within_half_the_queue=` )
    ( nurl_print ? < worst / y 2 `yes` `no` )
    ( nurl_print `\n` )
    ? >= worst / y 2 {
        ( nurl_print `worst_delay=` )
        ( nurl_println_int worst )
    } {}
    ^ 0
}
