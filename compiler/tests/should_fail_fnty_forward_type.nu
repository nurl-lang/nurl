// should_fail_fnty_forward_type.nu — a named type used inside a CLOSURE
// type must be declared before the struct that holds it.
//
// LLVM's parser makes a forward-referenced named type opaque, and an
// opaque struct is neither a valid function argument nor a valid return
// type — so the module is rejected at link time, at a column offset
// into a generated `= type` line, with no NURL source location:
//
//   %A = type { i64, { i64 (i8*, %C)*, i8* } }
//   error: invalid type for function argument
//
// And not everywhere: clang 18 on x86-64 Linux assembled it, while the
// macOS-arm64 and Windows toolchains did not. A green local build and a
// cryptic failure on someone else's platform is the worst shape a
// diagnostic can have, so this is rejected at the declaration, on every
// platform, naming the declaration to move.
//
// A forward reference as a plain FIELD stays legal — LLVM resolves that
// one when the definition arrives — and so do generic instantiations
// (`%Vec__i64`), which are emitted ahead of every user struct.

: A { i x ( @ i C ) f }

: C { i y }

@ main → i { ^ 0 }
