// diag_opt_payload_type_mismatch.nu — the payload of an option /
// result literal must be the type the option was declared over.
//
// Field 1 carries T's REAL type in both forms (`? i` lowers to
// `{ i1, i64 }`, `! i s` to `{ i1, i64, i8* }`), so a payload of a
// different type has nowhere to go. Two shapes reached past nurlc:
//
//   @ ?s { T 42 }    — nurlc exited 0 and CLANG said "insertvalue
//                      operand and field disagree in type: 'i64'
//                      instead of 'ptr'", naming neither the option
//                      nor the line to change.
//   @ ?i { T `x` }   — worse: compiled clean and RAN. The pointer was
//                      folded into the numeric slot with ptrtoint, so
//                      `?? o { T v → ^ v }` returned the low byte of a
//                      .rodata address. A silent miscompile.
//
// The pointer fold is the right representation for a slot that is a
// box, and the wrong one for a slot declared `i` — that distinction is
// what was missing, not the fold itself.
//
// This file pins the first shape (int payload into a string option);
// its twin diag_opt_payload_ptr_into_int.nu pins the second, because a
// declaration-level abort means one file can only demonstrate one.

@ main → i {
    : ?s o @ ?s { T 42 }
    ?? o { T v → ^ 1 F → ^ 0 }
}
