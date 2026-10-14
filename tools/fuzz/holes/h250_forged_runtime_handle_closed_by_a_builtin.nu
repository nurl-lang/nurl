// H250: safe code closed a made-up socket handle with the preamble builtin nurl_tcp_close: the runtime freed whatever was at that address.
// Closed: every preamble builtin that takes a runtime handle (nurl_tcp_*, nurl_proc_*, nurl_dir_list_*, …) is marked "nurl.raw": only an `unsafe` function may call it.
// main's compiler: UndefinedBehaviorSanitizer: misaligned access, then a free of a wild pointer.
@ main → i {
    ( nurl_tcp_close 123456789 )
    ( nurl_println `survived` )
    ^ 0
}
