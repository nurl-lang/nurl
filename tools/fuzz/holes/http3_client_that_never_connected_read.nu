// http3_client_that_never_connected_read: `h3_client_connect` to a name that does not resolve returns the
// null H3Client, and `h3_client_connected` of it read address 0 (and so
// did `quic_client_connected` of quic_client_connect's null client).
// Closed: an accessor of the null client panics instead of reading
// through it (h3_client_ok / quic_client_ok tell it).
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | runs-clean | h496 | `h3_client_connect` to a name that does not resolve returns the null H3Client, and `h3_client_connected` of it read address 0 (and so did `quic_client_connected` of quic_client_connect's null client).
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http3_client.nu`

@ main → i {
    : H3Client c ( h3_client_connect `nonexistent.invalid` 443 `x` 0 100 )
    ( nurl_println_int ? ( h3_client_connected c ) 1 0 )
    ^ 0
}
