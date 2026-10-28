// H477: `( tls_attach_full_until 4096 … )` ran a TLS handshake over the
// runtime socket record "at" 4096. Every other `tls_attach*` is on the
// compiler's list of functions that take a raw runtime handle; this one,
// with the deadline, was not.
// Closed: it is `raw`, so only an `unsafe` caller may call it (a program
// upgrades a TcpConn with tcp_starttls).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
$ `stdlib/core/vec.nu`
$ `stdlib/std/tls.nu`

@ main → i {
    ?? ( tls_attach_full_until 4096 `x` `` ( vec_new [u] ) 0 0 ) {
        T c → { ( nurl_println_int 1 ) }
        F e → { ( nurl_println_int 2 ) }
    }
    ^ 0
}
