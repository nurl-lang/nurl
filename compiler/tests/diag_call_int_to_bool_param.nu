// diag_call_int_to_bool_param.nu — a wider integer handed to a
// 'b' parameter. The truncation would keep only the low bit (2 → F,
// 3 → T) — this exact shape silently rewrote `( probe … 2 )` into
// `( probe … F )` inside toml_basic.nu when the coercion briefly
// existed. A parameter is a contract (like a return type): the
// comparison must be written out. The widening direction (b → i)
// stays a legal lossless coercion.
@ pick b c → i { ^ ? c 1 0 }

@ main → i {
    : i y 3
    ^ ( pick y )
}
