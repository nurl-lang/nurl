// diag_raw_runtime_handle.nu — tcp_conn_view takes the address of the
// runtime's own record for a socket as a plain integer: only unsafe code
// may call it; safe code uses the TcpConn the stdlib wraps it in.

$ `stdlib/std/net.nu`

@ main → i {
    : TcpConn c ( tcp_conn_view 3 )
    ^ 0
}
