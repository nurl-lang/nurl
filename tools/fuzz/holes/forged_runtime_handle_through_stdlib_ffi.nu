// forged_runtime_handle_through_stdlib_ffi: safe code called a foreign function the standard library declares (nurl_udp_close) with a made-up handle: a stdlib FFI declaration was callable from safe code, whatever its parameters meant.
// Closed: a stdlib FFI declaration that takes a runtime handle is written `unsafe & …`: only an `unsafe` function may call it.
// main's compiler: UndefinedBehaviorSanitizer: misaligned access.
// map: §3 | B | rejected | h251 | stdlib FFI nurl_udp_close called from safe code with forged handle
$ `stdlib/std/udp.nu`

@ main → i {
    ( nurl_udp_close 123456789 )
    ( nurl_println `survived` )
    ^ 0
}
