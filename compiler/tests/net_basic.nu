// net_basic.nu — exercises stdlib/std/net.nu error paths without
// touching any live socket. Deterministic on every CI host: only
// the err_kind plumbing + NetErr-name rendering are tested.
//
// Live loopback round-trip (accept/read/write) lives in
// `net_loopback.nu`, gated behind NURL_NET_TESTS=1.

$ `stdlib/std/net.nu`
$ `stdlib/core/string.nu`

@ print_label_str s label s value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ describe_listen_result s label ! TcpListener NetErr r → v {
    ?? r {
        T l → {
            ( print_label_str label `OK` )
            ( tcp_close_listener l )
        }
        F e → ( print_label_str label ( net_err_name e ) )
    }
}

@ main → i {
    // NetErr name table — sanity check, also forces every variant to be
    // exercised at link time so a renumber of the runtime tags blows
    // this test up before it spreads to higher layers.
    ( print_label_str `net_err_name(NetBind)` ( net_err_name # NetErr NetBind ) )
    ( print_label_str `net_err_name(NetAddrInUse)` ( net_err_name # NetErr NetAddrInUse ) )
    ( print_label_str `net_err_name(NetAccept)` ( net_err_name # NetErr NetAccept ) )
    ( print_label_str `net_err_name(NetRead)` ( net_err_name # NetErr NetRead ) )
    ( print_label_str `net_err_name(NetWrite)` ( net_err_name # NetErr NetWrite ) )
    ( print_label_str `net_err_name(NetClosed)` ( net_err_name # NetErr NetClosed ) )
    ( print_label_str `net_err_name(NetTimeout)` ( net_err_name # NetErr NetTimeout ) )
    ( print_label_str `net_err_name(NetOther)` ( net_err_name # NetErr NetOther ) )

    // tcp_listen rejects port 0 and ports outside [1,65535] in the
    // runtime; we surface that as NetBind on the NURL side.
    : !TcpListener NetErr r0 ( tcp_listen `127.0.0.1` 0 )
    ( describe_listen_result `listen_port_0` r0 )

    // Bad host literal — inet_pton fails. Same NetBind path.
    : !TcpListener NetErr rh ( tcp_listen `not.a.host` 8080 )
    ( describe_listen_result `listen_bad_host` rh )

    ^ 0
}
