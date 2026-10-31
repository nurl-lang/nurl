// forged_runtime_handle_through_a_conn_view: safe code wrapped a made-up number in a TcpConn (tcp_conn_view) and wrote to it: the runtime read the number as the address of its socket record.
// Closed: the standard library's functions that take a runtime handle as a plain integer (tcp_conn_view, tcp_conn_adopt, tls_attach*, tls_accept*) are raw, `unsafe` only; a program reaches sockets through TcpConn (tcp_connect, tcp_starttls, tls_accept_conn).
// main's compiler: UndefinedBehaviorSanitizer: misaligned access (a read through address 123456789).
// map: §3 | B | rejected | h249 | tcp_conn_view wraps a made-up number as a socket handle
$ `stdlib/std/net.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 65 )
    : TcpConn c ( tcp_conn_view 123456789 )
    ?? ( tcp_write_all c b ) { T _ → { ( nurl_println `ok` ) } F _ → { ( nurl_println `err` ) } }
    ^ 0
}
