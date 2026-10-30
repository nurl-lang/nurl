// udp_multicast_join_on_any_handle: `( nurl_udp_join_group 4096 … )` read the runtime socket record
// "at" 4096: std/udp.nu declared it (and nurl_udp_leave_group) without
// `unsafe`, between declarations that have it.
// Closed: both are declared `unsafe & …`; a program calls
// udp_join_group on a UdpSocket.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h499 | `( nurl_udp_join_group 4096 … )` read the runtime socket record "at" 4096: std/udp.nu declared it (and nurl_udp_leave_group) without `unsafe`, between declarations that have it.
$ `stdlib/std/udp.nu`

@ main → i {
    ( nurl_println_int ( nurl_udp_join_group 4096 `224.0.0.1` `` ) )
    ^ 0
}
