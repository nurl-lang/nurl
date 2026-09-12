// diag_ffi_ellipsis_not_last.nu — the '...' variadic marker with a
// parameter after it.
//
// The grammar is `ffi_decl = '&' STR '@' IDENT ffi_param* ( '...' )? '→'
// type`: the marker comes LAST and appears once. The parameter loop took
// a '...' wherever it landed and carried on, and the two consumers of the
// parameter list then disagreed about what the declaration had said.
//
// `s fmt ... i n` emitted `declare i64 @xpf(i8*, ..., i64)` — llvm-as:
// "expected ')' at end of argument list". A second '...' emitted
// `(i8*, ..., ...)`, the same way. A LEADING '...' is worse than either:
// the first parameter's `pct == 0` branch OVERWRITES the accumulated
// string, destroying the marker in the `declare` while the call-site
// signature keeps it — so the module declared `@xpf(i8*)` and emitted
// `call i64 (...) @xpf(i8* %r1)`, a variadic call against a non-variadic
// callee, which is a real ABI difference on every target that passes
// variadic arguments differently from fixed ones.
//
// Each of the three exited 0, and the news came from clang — or, for the
// leading form, from nowhere at all.
& `libc` @ xpf s fmt ... i n → i

@ main → i {
    ( nurl_print `unreachable\n` )
    ^ 0
}
