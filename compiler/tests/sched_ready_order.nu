// sched_ready_order.nu — on a saturated worker, fibers whose I/O became
// ready run in the order it became ready (agora #113).
//
// ONE worker. N readers park on their own loopback TCP connection; Y
// yielders keep the worker's run queue from ever emptying; a writer
// makes reader i's socket readable in order i, one per dispatch of its
// own. Each reader records how far its completion rank is from its
// arrival index.
//
// The rule: a fiber made runnable joins the TAIL of the order of
// runnable fibers (a fiber the netpoller wakes runs at once only on an
// idle worker), local and global queues are served oldest first, and
// the Linux netpoller is polled every 16th dispatch whatever is queued.
// A poll window then holds at most 16 arrivals, so a reader can be
// overtaken only within its own window: the displacement stays below
// 16, whatever N, Y and timing. The poll(2)/WSAPoll reactor thread of
// the other targets wakes in the order the fibers parked, which here is
// arrival order, and its wakes go through the same stamped queue.
//
// Before, a poll's first fiber ran at once and its next eight went to
// the worker's local queue, ahead of older readers spilled to the
// global queue; with a busy local queue the poller ran only every
// 128th dispatch and the global queue was served only when it found
// nothing. A reader spilled early ran after nearly every later one.
//
// TCP rather than socketpair so it runs on Windows too; 100 readers
// keep it under macOS's default 256 descriptors.
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: ~ i ranks 0
: ~ i max_disp 0
: ~ i woke_ready 0

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

@ __reader i idx TcpConn c → v {
    : i rc ( tcp_wait_io c T F - 0 1 )
    ? == rc 1 { = woke_ready + woke_ready 1 } {}
    : i r ranks
    = ranks + ranks 1
    : i d ? > r idx - r idx - idx r
    ? > d max_disp { = max_disp d } {}
    ( tcp_close_conn c )
}

@ __yielder i n → v {
    : ~ i k 0
    ~ < k n {
        ( yield )
        = k + k 1
    }
}

@ __writer ( Vec TcpConn ) clients → v {
    ~ > ( vec_len [TcpConn] clients ) 0 {
        ?? ( vec_remove [TcpConn] clients 0 ) {
            T c → {
                : !v NetErr w ( tcp_write_str c `x` )
                ( tcp_close_conn c )
            }
            F → {}
        }
        ( yield )
    }
}

@ main → i {
    : i n 100
    : i y 7
    ( runtime_init 1 )
    : TcpListener l ?? ( tcp_listen `127.0.0.1` 0 ) { T x → x F _ → { ( nurl_print `listen failed\n` ) ^ 1 } }
    : i port ( __port l )
    : ( Vec TcpConn ) clients ( vec_new [TcpConn] )
    : ~ i i 0
    ~ < i n {
        // Off a fiber: connect, then accept it, one at a time, so the
        // accept queue never holds more than one.
        ?? ( tcp_connect `127.0.0.1` port ) {
            T c → { ( vec_push [TcpConn] clients c ) }
            F _ → { ( nurl_print `connect failed\n` ) ^ 1 }
        }
        ?? ( tcp_accept l ) {
            T s → {
                : i idx i
                ( spawn_owned \ → v { ( __reader idx s ) } )
            }
            F _ → { ( nurl_print `accept failed\n` ) ^ 1 }
        }
        = i + i 1
    }
    = i 0
    ~ < i y {
        ( spawn_owned \ → v { ( __yielder 20000 ) } )
        = i + i 1
    }
    ( spawn_owned \ → v { ( __writer clients ) } )
    ( runtime_run )
    ( runtime_shutdown )
    ( tcp_close_listener l )
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
