// H498: `( nurl_tcp_sendfile 4096 0 0 1 )` read the runtime socket record
// "at" 4096: std/net.nu declared it without `unsafe`.
// Closed: it is declared `unsafe & …`; a program calls tcp_sendfile on a
// TcpConn.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/std/net.nu`

@ main → i {
    ( nurl_println_int ( nurl_tcp_sendfile 4096 0 0 1 ) )
    ^ 0
}
