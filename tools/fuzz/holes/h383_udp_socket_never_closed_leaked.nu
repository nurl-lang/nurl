// H383: a UdpSocket never closed leaked its runtime record and its fd: the contract was "udp_close exactly once", which nothing checked, and the handle had no drop.
// Closed: as h382 — the socket's last owner closes it (agora #139).
// v0.79.1: accepted; LeakSanitizer reported 32 bytes from nurl_udp_bind.
$ `stdlib/std/udp.nu`

@ main → i {
    ?? ( udp_bind `127.0.0.1` 0 ) { T s → { ( nurl_println `bound, never closed` ) } F _ → {} }
    ^ 0
}
