// fiber_owns_option_payload.nu — a fiber handed a TcpConn taken out of an
// option / result binding, with an owned local beside it (agora #140).
//
// A closure handed to spawn_owned that captures the payload `c` of a
// match on `cr` — or `c` bound from it (`: TcpConn c ?? cr { T x → x … }`)
// — and a channel made here moves both: the payload's owner goes with
// it, so the thread crossing check (docs/MEMORY.md §6.5) sees the fiber
// as the connection's only owner. Before, the env was built owning a
// copy of `c` while `cr` kept the original, and the check panicked: "a
// 'TcpConn' crosses … another owner … left on this side".
// requires: live

$ `stdlib/std/net.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/string.nu`

@ use TcpConn c ( Channel i ) done → v {
    ?? ( tcp_write_str c `from the fiber` ) { T _ → { ( nurl_println `a fiber owns the connection` ) } F _ → { ( nurl_println `write failed` ) } }
    ( chan_send [i] done 1 )
}

@ port_of String a → i {
    : ~ i p 0
    : ~ i k 0
    ~ < k ( string_len a ) {
        : i ch ( string_get a k )
        ? == ch 58 { = p 0 } { ? & >= ch 48 <= ch 57 { = p + * p 10 - ch 48 } {} }
        = k + k 1
    }
    ^ p
}

@ main → i {
    ( runtime_init 2 )
    : TcpListener l ?? ( tcp_listen `127.0.0.1` 0 ) { T x → x F _ → { ^ 1 } }
    : i port ( port_of ( tcp_local_addr l ) )
    // The payload of a match on the binding.
    : !TcpConn NetErr cr ( tcp_connect `127.0.0.1` port )
    ?? cr {
        T c → {
            : ( Channel i ) done ( chan_new [i] )
            ( spawn_owned \ → v { ( use c done ) } )
        }
        F _ → { ( nurl_println `connect failed` ) }
    }
    // A binding of the payload.
    : !TcpConn NetErr cr2 ( tcp_connect `127.0.0.1` port )
    : TcpConn c2 ?? cr2 { T x → x F _ → { ^ 1 } }
    : ( Channel i ) done2 ( chan_new [i] )
    ( spawn_owned \ → v { ( use c2 done2 ) } )
    ( runtime_run )
    ( runtime_shutdown )
    ( nurl_println `done` )
    ^ 0
}
