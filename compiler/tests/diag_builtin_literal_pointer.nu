// diag_builtin_literal_pointer.nu — an integer literal where the
// parameter is a pointer. An integer HANDLE in a binding is converted
// with inttoptr (the wasm ABI needs the call's signature to match the
// declaration), but a literal is not a handle: `( nurl_print 5 )`
// compiled clean and the program segfaulted dereferencing 5. Zero is the
// one literal that means something in a pointer position — the null
// pointer — and it is still accepted.

@ main → i {
    ( nurl_print 5 )
    ^ 0
}
