// should_fail_ffi_sig_conflict.nu — one linker symbol, one ABI.
//
// `stdlib/core/posix.nu` declares open(2) as C does:
//
//     & `c` @ open s path i32 flags ... → i32
//
// Restating it with `i` where C says `int`, and without the ellipsis,
// describes a DIFFERENT function under the same linker name. Both
// declarations cannot be emitted (LLVM rejects a redefinition), so the
// first one wins the `declare` — while every later one silently
// overwrote the call-site metadata. Calls were then lowered against a
// signature the module never declared:
//
//     call i64 (i8*, i32, ...) @open(i8* %p, i64 %f)
//
// nurlc exited 0 and clang delivered the news, about generated IR.
// packages/yoloe hit exactly this and could not be built at all.
//
// Identical redeclarations stay legal — two modules declaring the same
// extern is ordinary, and the dedup exists for it. Only a DISAGREEMENT
// is an error, and it points at the `&` rather than at the next
// declaration the lexer had already reached.

$ `stdlib/core/posix.nu`

& `c` @ open s path i flags → i

@ main → i {
    : i fd ( open `/dev/null` 0 )
    ^ ? > fd 0 0 1
}
