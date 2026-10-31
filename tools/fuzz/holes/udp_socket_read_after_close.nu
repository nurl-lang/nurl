// udp_socket_read_after_close: a UdpSocket read after udp_close read freed memory: the handle was the runtime record's address (`: UdpSocket { s raw }`, no drop), udp_close freed the record, and every copy of the handle still named it.
// Closed: a UdpSocket is a shared handle with a drop (`UdpSocketImpl`, `% Drop` → nurl_udp_close); udp_close only shuts the socket down (nurl_udp_shutdown), the record lives until its last owner drops it, and every copy then sees a closed socket (agora #139).
// v0.79.1: accepted; ASan reported heap-use-after-free in nurl_udp_local_addr.
// map: §6.4 | B | runs-clean | h382 | a UdpSocket was the runtime record's address with no drop; udp_close freed the record every copy still named: a shared handle with a drop, udp_close only stops the socket
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
