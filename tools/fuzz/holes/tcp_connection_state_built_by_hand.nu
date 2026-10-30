// tcp_connection_state_built_by_hand: a `TcpConnImpl` literal of the program's own
// (`@ TcpConnImpl { 4096 0 0 T }`) is a connection state that owns the
// runtime socket record "at" 4096: its drop closed it.
// Closed: TcpConnImpl is sealed (`raw :`); a TcpConn is made by the
// library (tcp_connect, tcp_accept, tcp_conn_adopt for `unsafe` code).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h488 | a `TcpConnImpl` literal of the program's own (`@ TcpConnImpl { 4096 0 0 T }`) is a connection state that owns the runtime socket record "at" 4096: its drop closed it.
$ `stdlib/std/net.nu`

@ main → i {
    : TcpConnImpl c @ TcpConnImpl { 4096 0 0 T }
    ( nurl_println_int . c kind )
    ^ 0
}
