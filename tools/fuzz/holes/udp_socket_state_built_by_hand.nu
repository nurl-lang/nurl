// udp_socket_state_built_by_hand: a `UdpSocketImpl` literal of the program's own freed the runtime
// socket record "at" 4096 when it was dropped.
// Closed: UdpSocketImpl is sealed (`raw :`).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h490 | a `UdpSocketImpl` literal of the program's own freed the runtime socket record "at" 4096 when it was dropped.
$ `stdlib/std/udp.nu`

@ main → i {
    : UdpSocketImpl u @ UdpSocketImpl { 4096 }
    ( nurl_println_int . u raw )
    ^ 0
}
