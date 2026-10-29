// H489: a `TcpListenerImpl` literal of the program's own closed the
// runtime socket record "at" 4096 when it was dropped.
// Closed: TcpListenerImpl is sealed (`raw :`).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/std/net.nu`

@ main → i {
    : TcpListenerImpl l @ TcpListenerImpl { 4096 0 0 0 }
    ( nurl_println_int . l is_tls )
    ^ 0
}
