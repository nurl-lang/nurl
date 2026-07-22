// struct_lit_int_field_clash.nu — a bare integer supplied for a PLAIN
// named-struct field in an aggregate literal must be a compile error.
// `@ Outer { g g 0 }` (an old 3-value literal kept after Outer grew a
// struct-typed field) used to emit `insertvalue %Outer i64 0` — invalid
// IR that nurlc accepted (rc 0) and only clang rejected, with no source
// location. Enum fields (variant tags) and single-pointer-handle structs
// (Vec/String) still coerce legally.

: Gv { i id }

: Outer { Gv a Gv b Gv c i n }

@ main → i {
    : Gv g @ Gv { 7 }
    : Outer o @ Outer { g g 0 }
    ^ . o n
}
