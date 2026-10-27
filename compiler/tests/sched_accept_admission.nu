// sched_accept_admission.nu — on a saturated worker, a connection is
// accepted within one poll window of arriving (agora #113).
//
// ONE worker. Y yielders keep its run queue from ever emptying; each
// dispatch of one does ~20 µs of work and counts itself in `ticks`. An
// acceptor fiber accepts on a loopback listener; a client THREAD — the
// outside world — connects N times, one at a time, and notes `ticks` as
// each connect returns. The acceptor notes `ticks` as each accept
// returns. A connection's admission delay is the yielder dispatches
// between the two.
//
// The rule (Admission, stdlib/runtime_ffi.c "Service order"): a fiber
// parked in an accept runs as soon as its listener is polled ready,
// ahead of everything queued. The Linux netpoller is polled every 16th
// dispatch, so the delay stays within 16; the poll(2) reactor thread of
// the other targets puts the acceptor at the head of the run queue, so
// it runs at the worker's next dispatch, and the unikernel's socket
// layer (nolibc, where the client thread is a coroutine too) wakes it to
// the head of the bare runtime's run queue. Every way the delay is far
// below Y, whatever N and timing.
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

@ __acceptor TcpListener l i n Atomic ticks Atomic done ( Channel i ) acc → v {
    : ~ i k 0
    ~ < k n {
        ?? ( tcp_accept_transport l ) {
            T c → {
                : b _s ( chan_send [i] acc ( atomic_load ticks ) )
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
    : ( Channel i ) acc ( chan_new [i] )
    // The acceptor first: it parks in its accept before the yielders
    // fill the queue, so every connection meets it parked.
    ( spawn_owned \ → v { ( __acceptor l n ticks done acc ) } )
    : ~ i i 0
    ~ < i y {
        ( spawn_owned \ → v { ( __yielder ticks done ) } )
        = i + i 1
    }
    // The outside world: connect, note the tick, close, let the server
    // get busy again.
    : Atomic ct ( Atomic_share ticks )
    : ( Channel i ) cv ( chan_new [i] )
    : !Thread ThreadErr client ( thread_spawn \ → v {
        : ~ i j 0
        ~ < j n {
            ?? ( tcp_connect `127.0.0.1` port ) {
                T c → {
                    : b _s ( chan_send [i] cv ( atomic_load ct ) )
                    ( tcp_close_conn c )
                }
                F _ → { : b _s ( chan_send [i] cv -1 ) }
            }
            ( sleep_ms 1 )
            = j + j 1
        }
    } )
    ( runtime_run )
    ?? client { T t → { : i _j ( thread_join t ) } F _ → {} }
    ( runtime_shutdown )
    ( tcp_close_listener l )
    : ~ i worst 0
    : ~ i bad 0
    : ~ i got 0
    : ~ b more T
    ~ more {
        ?? ( chan_try_recv [i] acc ) {
            T a → {
                : i c ?? ( chan_try_recv [i] cv ) { T x → x F → -1 }
                ? < c 0 { = bad + bad 1 } {
                    : i d ? > a c - a c 0
                    ? > d worst { = worst d } {}
                }
                = got + got 1
            }
            F → { = more F }
        }
    }
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
