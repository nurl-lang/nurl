// net_basic.nu — stdlib/std/net.nu's bind-time surface: the err_kind
// plumbing, NetErr-name rendering, and the two answers `tcp_listen`
// can give about an address (ephemeral bind, unparseable host).
//
// It binds on the loopback interface — hence `requires: live` — but
// never accepts, connects or transfers: the round-trip lives in
// `net_loopback.nu`. Deterministic on any host with a loopback
// interface, since the ephemeral port is never printed, only asserted
// to exist.
// requires: live

$ `stdlib/std/net.nu`

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

    // Port 0 = "kernel picks an ephemeral port" — a successful bind, and
    // the only way to take a port without racing whoever else wants it.
    // `tcp_local_addr` reports what was picked; the port half must be a
    // real, non-zero number, or the caller has a listener it cannot tell
    // anyone how to reach. (This assertion read `NetBind` until the
    // runtime stopped rejecting port 0 — the test had been written from
    // the implementation, so the golden pinned the defect.)
    : !TcpListener NetErr r0 ( tcp_listen `127.0.0.1` 0 )
    ?? r0 {
        T l → {
            ( print_label_str `listen_port_0` `OK` )
            : String la ( tcp_local_addr l )
            ( print_label_str `local_addr_host` ? ( string_starts_with la `127.0.0.1:` ) `T` `F` )
            ( print_label_str `local_addr_port_assigned` ? ( string_ends_with la `:0` ) `F` `T` )
            ( string_free la )
            ( tcp_close_listener l )
        }
        F e → ( print_label_str `listen_port_0` ( net_err_name e ) )
    }

    // Bad host literal — inet_pton fails. Same NetBind path.
    : !TcpListener NetErr rh ( tcp_listen `not.a.host` 8080 )
    ( describe_listen_result `listen_bad_host` rh )

    ^ 0
}
