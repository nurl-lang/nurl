// diag_duplicate_type.nu — the flat-namespace guard for TYPES and GLOBALS,
// the twin of diag_duplicate_fn.
//
// A second `: Name { … }` used to emit a second `%Name = type` and die inside
// LLVM with no source location; a second `: ~ name` was two `@name = global`
// emissions — and two files silently SHARING one mutable global by accident
// is worse than the link error it happened to die with. Both now die in the
// front end with both locations, while they are still known.
$ `compiler/tests/diag_duplicate_type_mod.nu`

: Shape {
    i x
    i y
}

: ~ i g_shared_count 5

@ main → i {
    ^ g_shared_count
}
