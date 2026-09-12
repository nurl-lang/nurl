// diag_default_on_inout.nu — a default value on an 'inout' parameter.
//
// An inout argument is the ADDRESS of a mutable binding the callee writes
// through; a default is a value, and has none. The call site spliced the
// literal into the pointer slot — `( bump 1 )` emitted
// `call void @bump(i64 1, i64 0)` against `define void @bump(i64, i64*)`,
// which clang accepts under opaque pointers and which stores through a
// null pointer at run time: a clean compile and a segfault.
//
// The grammar has always said defaults are not available on 'inout' or
// 'sink'; generic, FFI and variadic declarations — the other three in the
// same sentence — already rejected one at the declaration.
@ bump i by inout i n = 0 → v { = n + n by }

@ main → i {
    : ~ i k 5
    ( bump 1 )
    ^ k
}
