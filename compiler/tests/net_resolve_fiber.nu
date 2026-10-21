// net_resolve_fiber.nu — name resolution on a fiber runs off the worker.
//
// On ONE worker, a fiber resolves `localhost` (a name: /etc/hosts via
// getaddrinfo, so it goes to the runtime's resolver threads) while a
// second fiber yields in a loop, counting. The resolving fiber parks
// until its lookup completes, so the yielder can run during the
// lookups; had getaddrinfo run on the worker, it never could. An
// /etc/hosts answer is often finished before its fiber looks (on a busy
// machine the woken resolver thread can preempt the submitting worker),
// which proves nothing either way, so the runtime's test hook makes
// every pool lookup take 20 ms first: the fiber then always waits, and
// the yielder must run meanwhile. On the blocking implementation it
// never does.
//
// dns_reverse (getnameinfo, 127.0.0.1 → its /etc/hosts name) the same.
//
// Then it connects to `localhost`, with a deadline. `localhost`
// commonly resolves to ::1 first and the listener is on 127.0.0.1 only,
// so this also exercises the fallback to the next address after a
// refused one. A numeric address takes the in-process fast path.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/dns.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`

& `c` @ nurl_dns_test_delay_ms i ms → v

unsafe @ __slow_lookups i ms → v { ( nurl_dns_test_delay_ms ms ) }

: ~ i yields 0
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

@ __say s label s v → v {
    ( nurl_print label )
    ( nurl_print v )
    ( nurl_print `\n` )
}

@ __has_loopback ( Vec String ) ips → b {
    : ~ i k 0
    ~ < k ( vec_len [String] ips ) {
        : b hit ?? ( vec_get [String] ips k ) {
            T ip → | != 0 ( nurl_str_eq ( string_data ip ) `127.0.0.1` ) != 0 ( nurl_str_eq ( string_data ip ) `::1` )
            F → F
        }
        ? hit { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ main → i {
    ( runtime_init 1 )
    ( __slow_lookups 20 )
    : TcpListener l ?? ( tcp_listen `127.0.0.1` 0 ) { T x → x F _ → { ^ 1 } }
    : i port ( __port l )

    : ( @ v ) yielder \ → v {
        ~ == stop 0 {
            = yields + yields 1
            ( yield )
        }
    }
    : ( @ v ) resolver \ → v {
        // The lookups alone: a connect parks too, and would count.
        : ~ i found 0
        : ~ i during 0
        : ~ i k 0
        ~ < k 5 {
            : i y0 yields
            ?? ( dns_resolve `localhost` ) {
                T ips → ? ( __has_loopback ips ) { = found + found 1 } {}
                F e → ( __say `dns_resolve_err=` ( net_err_name e ) )
            }
            = during + during - yields y0
            = k + k 1
        }
        ( __say `dns_resolve_loopback_every_time=` ? == found k `yes` `no` )
        ( __say `yielder_ran_during_lookups=` ? > during 0 `yes` `no` )

        // The reverse lookup (getnameinfo) takes the same pool.
        : ~ i named 0
        = during 0
        = k 0
        ~ < k 5 {
            : i y1 yields
            ?? ( dns_reverse `127.0.0.1` ) {
                T name → ? > ( string_len name ) 0 { = named + named 1 } {}
                F → {}
            }
            = during + during - yields y1
            = k + k 1
        }
        ( __say `dns_reverse_named_every_time=` ? == named k `yes` `no` )
        ( __say `yielder_ran_during_reverse=` ? > during 0 `yes` `no` )

        : ~ i ok 0
        = k 0
        ~ < k 5 {
            ?? ( tcp_connect_timeout `localhost` port 5000 ) {
                T c → {
                    = ok + ok 1
                    ( tcp_close_conn c )
                }
                F e → ( __say `localhost_err=` ( net_err_name e ) )
            }
            = k + k 1
        }
        ( __say `localhost_connects=` ( nurl_str_int ok ) )

        ?? ( tcp_connect `127.0.0.1` port ) {
            T c → {
                ( __say `numeric=` `connected` )
                ( tcp_close_conn c )
            }
            F e → ( __say `numeric=` ( net_err_name e ) )
        }
        = stop 1
    }
    ( spawn yielder )
    ( spawn resolver )
    ( runtime_run )
    ( runtime_shutdown )
    ^ 0
}
