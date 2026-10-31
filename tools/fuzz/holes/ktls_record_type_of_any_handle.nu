// ktls_record_type_of_any_handle: `( nurl_ktls_rtype 4096 )` read the runtime socket record "at"
// 4096: std/tls.nu declared the runtime entry point without `unsafe`, so
// any program could pass it a made-up handle.
// Closed: it is declared `unsafe & …`, as the other handle entry points
// are.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h497 | `( nurl_ktls_rtype 4096 )` read the runtime socket record "at" 4096: std/tls.nu declared the runtime entry point without `unsafe`, so any program could pass it a made-up handle.
$ `stdlib/std/tls.nu`

@ main → i {
    ( nurl_println_int ( nurl_ktls_rtype 4096 ) )
    ^ 0
}
