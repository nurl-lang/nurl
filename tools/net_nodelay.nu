// tools/net_nodelay.nu — every TCP connection NURL makes or accepts has
// Nagle off (TCP_NODELAY), read back from the kernel with getsockopt.
//
// The connect side was missing it: a client's small writes (ClientHello,
// Finished, request) then waited ~40 ms each for a delayed ACK, which
// tls-bench measured as 42 ms per new http-client connection.
//
// Exit 0 when both ends report TCP_NODELAY = 1. Linux / macOS (IPPROTO_TCP
// 6, TCP_NODELAY 1 on both).

$ `stdlib/std/net.nu`

unsafe & `libc` @ getsockopt i fd i level i name *u val *u len → i

// TCP_NODELAY on the socket behind a NURL connection handle: 1, 0, or -1
// when getsockopt fails.
unsafe @ nodelay_of TcpConn c → i {
    : i fd ( nurl_tcp_get_fd ( tcp_conn_fd c ) )
    : ( Vec u ) val ( vec_zeroed [u] 4 )
    : ( Vec u ) len ( vec_zeroed [u] 4 )
    ( vec_put [u] len 0 # u 4 )
    ? != ( getsockopt fd 6 1 ( vec_data [u] val ) ( vec_data [u] len ) ) 0 { ^ - 0 1 } {}
    // A C int; any non-zero byte means on (both hosts are little-endian).
    : i b0 ?? ( vec_get [u] val 0 ) { T x → # i x F _ → 0 }
    ^ ? != b0 0 1 0
}

unsafe @ main → i {
    : i port 18977
    : TcpListener l ?? ( tcp_listen `127.0.0.1` port ) {
        T x → x
        F e → { ( nurl_eprintln ( net_err_name e ) ) ^ 2 }
    }
    : TcpConn cli ?? ( tcp_connect `127.0.0.1` port ) {
        T x → x
        F e → { ( nurl_eprintln ( net_err_name e ) ) ^ 2 }
    }
    : TcpConn srv ?? ( tcp_accept l ) {
        T x → x
        F e → { ( nurl_eprintln ( net_err_name e ) ) ^ 2 }
    }
    : i c ( nodelay_of cli )
    : i s ( nodelay_of srv )
    ( nurl_eprint `connected TCP_NODELAY=` )
    ( nurl_eprint ( nurl_str_int c ) )
    ( nurl_eprint `  accepted TCP_NODELAY=` )
    ( nurl_eprintln ( nurl_str_int s ) )
    ^ ? & == c 1 == s 1 0 1
}
