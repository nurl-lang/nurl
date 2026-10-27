// OPEN in v0.79.1 — a UdpSocket read after udp_close: the handle is the runtime record's address (`: UdpSocket { s raw }`, no drop), udp_close frees the record, and every copy of the handle still names it. ASan: heap-use-after-free in nurl_udp_local_addr (agora #139; the fix needs a handle with a drop, which needs #140).
$ `stdlib/std/udp.nu`
$ `stdlib/core/string.nu`

@ main → i {
    ?? ( udp_bind `127.0.0.1` 0 ) {
        T s → {
            ( udp_close s )
            : String a ( udp_local_addr s )
            ( nurl_println ( string_data a ) )
        }
        F _ → {}
    }
    ^ 0
}
