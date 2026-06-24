// tls12_prf.nu — the TLS 1.2 PRF (P_SHA256) against the well-known
// RFC 5246 "test label" known-answer vector.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `packages/tls/src/tls.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ main → i {
    : ( Vec u ) secret ( hx `9bbe436ba940f017b17652849a71db35` )
    : ( Vec u ) seed ( hx `a0ba9f936cda311827a6f796ffd5198c` )
    : ( Vec u ) out ( __prf12 secret `test label` seed 100 )
    : String h ( bytes_to_hex out )
    ? ( nurl_str_eq ( string_data h ) `e3f229ba727be17b8d122620557cd453c2aab21d07c3d495329b52d4e61edb5a6b301791e90d35c9c9a46b4e14baf9af0fa022f7077def17abfd3797c0564bab4fbc91666e9def9b97fce34f796789baa48082d122ee42c5a72e5a5110fff70187347b66` ) {
        ( nurl_print `tls12_prf: PASS\n` ) ^ 0
    } {
        ( nurl_print `tls12_prf: FAIL ` ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` ) ^ 1
    }
}
