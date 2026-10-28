// H444: `@ TcpConnImpl { 4096 0 0 T }`: the state behind a TcpConn is a
// plain struct, and a literal of it in safe code was accepted; its
// `% Drop` handed the made-up number 4096 to nurl_tcp_close as the address
// of a runtime record. The same for RawBlock (whose drop frees its `s`),
// FileImpl, BufReaderImpl, UdpSocketImpl, __CProcResult, ThreadImpl and
// every other library struct with its own destructor.
// Closed: a standard-library struct with its own `% Drop` is sealed —
// only the library builds it or writes its fields (__ty_sealed).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/std/net.nu`

@ main → i {
    : TcpConnImpl x @ TcpConnImpl { 4096 0 0 T }
    ( nurl_print `done\n` )
    ^ 0
}
