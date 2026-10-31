// tls_socket_writer_given_any_handle: `( _tls_sock_write 4096 v )` wrote to the runtime socket record
// "at" 4096: the helper takes a runtime handle as a plain integer, which
// only an `unsafe` function may pass, under one underscore
// (`_tls_sock_write2` too).
// Closed: both are `raw`.
// v0.80.0: accepted; AddressSanitizer reported SEGV.
// map: §3.3d | B | rejected | h485 | `( _tls_sock_write 4096 v )` wrote to the runtime socket record "at" 4096: the helper takes a runtime handle as a plain integer, which only an `unsafe` function may pass, under one underscore…
$ `stdlib/core/vec.nu`
$ `stdlib/std/tls.nu`

@ main → i {
    : ( Vec u ) v ( vec_zeroed [u] 8 )
    : b r ( _tls_sock_write 4096 v )
    ( nurl_println_int ? r 1 0 )
    ^ 0
}
