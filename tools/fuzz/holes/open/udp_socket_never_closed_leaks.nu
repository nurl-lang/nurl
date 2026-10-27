// OPEN in v0.79.1 — a UdpSocket that is never closed leaks its runtime record and its fd: its contract is "udp_close exactly once", which nothing checks, and it has no drop. LSan (use_stacks=0): 32 bytes from nurl_udp_bind (agora #139).
$ `stdlib/std/udp.nu`

@ main → i {
    ?? ( udp_bind `127.0.0.1` 0 ) { T s → { ( nurl_println `bound, never closed` ) } F _ → {} }
    ^ 0
}
