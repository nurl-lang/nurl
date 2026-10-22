// net_connect_fiber_timeout.nu — a TCP connect that has to wait must not
// hold its worker, and a connect deadline must end it.
//
// The black hole is a local listener whose accept queue is full: Linux
// completes handshakes into the accept queue until it holds backlog+1
// connections and DROPS every SYN after that (the listen-overflow drop
// runs ahead of SYN cookies, which only cover a full SYN queue), so the
// next connect sits in SYN_SENT retransmitting until its deadline.
// That is deterministic and needs no route, unlike a non-routable
// address — which answers ENETUNREACH at once on a host without a
// default route and hangs on one with it.
// (So the test runs on Linux only: test_skips.sh.)
//
//   1. Off a fiber: fill the queue — connect with a 200 ms deadline
//      until one reports NetTimeout (tcp_connect_timeout's poll(2)
//      path), then time one more.
//   2. On a fiber, ONE worker: a connect to the full listener with a
//      300 ms deadline, beside a fiber ticking every 10 ms. If the
//      connect blocked the worker the ticker could not run until it
//      returned; it must tick throughout, and the connect must come
//      back NetTimeout on time.
//   3. On a fiber: a refused connect (a port nothing listens on) fails
//      at once with the transport's error, and a TLS connect to it
//      reports that error too — not NetTlsHandshake.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`

: ~ i ticks 0
: ~ i stop 0

@ __port TcpListener l → i {
    : String address ( tcp_local_addr l )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ( string_free address )
    ^ port
}

@ __closed_port TcpListener l → i {
    : i p ( __port l )
    ( tcp_close_listener l )
    ^ p
}

@ __say s label s v → v {
    ( nurl_print label )
    ( nurl_print v )
    ( nurl_print `\n` )
}

@ __result ! TcpConn NetErr r → s {
    ^ ?? r {
        T c → {
            ( tcp_close_conn c )
            ^ `connected`
        }
        F e → ( net_err_name e )
    }
}

@ main → i {
    ( runtime_init 1 )
    : TcpListener full ?? ( tcp_listen_with_backlog `127.0.0.1` 0 1 ) { T l → l F _ → { ^ 1 } }
    : i fport ( __port full )

    // 1. Fill the accept queue, off a fiber.
    : ( Vec TcpConn ) held ( vec_new [TcpConn] )
    : ~ b filled F
    : ~ i k 0
    ~ & ! filled < k 16 {
        ?? ( tcp_connect_timeout `127.0.0.1` fport 200 ) {
            T c → ( vec_push [TcpConn] held c )
            F e → ? ( net_is_timeout e ) { = filled T } { ^ 2 }
        }
        = k + k 1
    }
    ( __say `queue_full=` ? filled `yes` `no` )
    : i t0 ( monotonic_ns )
    : s off ( __result ( tcp_connect_timeout `127.0.0.1` fport 150 ) )
    : i off_ms ( elapsed_ms_since t0 )
    ( __say `off_fiber=` off )
    ( __say `off_fiber_on_time=` ? & >= off_ms 120 < off_ms 3000 `yes` `no` )

    // A port with nothing behind it: bind one, learn it, close it.
    : i dead ?? ( tcp_listen `127.0.0.1` 0 ) { T l → ( __closed_port l ) F _ → { ^ 3 } }
    ^ ( __fiber_part fport dead )
}

@ __fiber_part i fport i dead → i {
    : ( @ v ) ticker \ → v {
        ~ == stop 0 {
            ( sleep_ms 10 )
            = ticks + ticks 1
        }
    }
    : ( @ v ) blocked \ → v {
        // 2. The black hole, on the ticker's worker.
        : i before ticks
        : i t1 ( monotonic_ns )
        : s r ( __result ( tcp_connect_timeout `127.0.0.1` fport 300 ) )
        : i ms ( elapsed_ms_since t1 )
        : i during - ticks before
        ( __say `fiber=` r )
        ( __say `fiber_on_time=` ? & >= ms 250 < ms 3000 `yes` `no` )
        ( __say `ticker_ran_during_connect=` ? >= during 10 `yes` `no` )

        // 3. Refused, plain and TLS.
        : i t2 ( monotonic_ns )
        ( __say `refused=` ( __result ( tcp_connect_timeout `127.0.0.1` dead 5000 ) ) )
        ( __say `refused_tls=` ( __result ( tcp_connect_tls `127.0.0.1` dead `localhost` 0 ) ) )
        ( __say `refused_fast=` ? < ( elapsed_ms_since t2 ) 1000 `yes` `no` )
        = stop 1
    }
    ( spawn ticker )
    ( spawn blocked )
    ( runtime_run )
    ( runtime_shutdown )
    ^ 0
}
