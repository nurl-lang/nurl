// diag_call_names_a_value.nu — a call whose callee names a value.
//
// The read side has carried this taxonomy for years: gen_ident knows a
// `__ptr` is a local binding, a `__global` a const or enum variant, a
// `__param` a by-value parameter, and it refuses a name that is none of
// them rather than emit an undefined `%name` only clang would catch.
// The CALL side had no such guard. `: i a 5` then `( a )` emitted
// `call i64 @a()` — a reference to a global nothing defines — and this
// program, calling a CONST, emitted `call i64 @MAX()` against
// `@MAX = global i64 10`: clang accepts that (the global has an address)
// and the program jumps into the constant. A clean compile and a
// segfault.
//
// One deleted token produces this shape everywhere — `( print_vec a )`
// minus its callee name is `( a )` — so the token-deletion sweep found
// it in three hundred mutants across thirty corpus programs, once the
// sweep learned to ask clang whether the IR it accepted was valid.

: i MAX 10

@ main → i {
    ( MAX )
    ^ 0
}
