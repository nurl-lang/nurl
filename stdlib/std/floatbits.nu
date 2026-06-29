// stdlib/std/floatbits.nu — IEEE-754 bit reinterpretation and binary float I/O.
//
// NURL's `#` cast between `i` and `f` converts the VALUE (5 → 5.0); this module
// reinterprets the BIT PATTERN — the operation binary formats need. Backed by a
// zero-allocation runtime bitcast (memcpy, strict-aliasing-safe), correct for
// every pattern including NaN, ±Inf and subnormals.
//
// Use cases: binary serialization (msgpack / protobuf / wasm / audio sample
// formats), hashing float data, turning a random u64 into a float, and the
// pure-NURL wasm runtime. Note `bytes_push_float` in std/bytes.nu writes the
// `%g` TEXT of a float; the `_f64_`/`_f32_` helpers here write the 8-/4-byte
// IEEE-754 BINARY encoding.
//
//   f64_to_bits / bits_to_f64        f64 ↔ its 64-bit pattern (in an `i`)
//   f32_to_bits / bits_to_f32        f32 ↔ its 32-bit pattern (low 32 bits)
//   bytes_push_f64_le/_be  bytes_read_f64_le/_be → ?f
//   bytes_push_f32_le/_be  bytes_read_f32_le/_be → ?f32

$ `stdlib/std/bytes.nu`

// ── runtime bitcast bridge (memcpy in runtime.c) ─────────────────
& `c` @ nurl_f64_to_bits f x → i

& `c` @ nurl_bits_to_f64 i b → f

& `c` @ nurl_f32_to_bits f32 x → i

& `c` @ nurl_bits_to_f32 i b → f32

// ── reinterpret ──────────────────────────────────────────────────

// f64 → its 64-bit IEEE-754 pattern as a (signed) i.
@ f64_to_bits f x → i { ^ ( nurl_f64_to_bits x ) }

// 64-bit pattern → the f64 it encodes.
@ bits_to_f64 i b → f { ^ ( nurl_bits_to_f64 b ) }

// f32 → its 32-bit IEEE-754 pattern, zero-extended into the low 32 bits of an i.
@ f32_to_bits f32 x → i { ^ ( nurl_f32_to_bits x ) }

// Low 32 bits of `b` → the f32 they encode.
@ bits_to_f32 i b → f32 { ^ ( nurl_bits_to_f32 b ) }

// ── binary float I/O (IEEE-754, explicit endianness) ─────────────

@ bytes_push_f64_be ( Vec u ) v f x → v { ( bytes_push_u64_be v # u64 ( f64_to_bits x ) ) }

@ bytes_push_f64_le ( Vec u ) v f x → v { ( bytes_push_u64_le v # u64 ( f64_to_bits x ) ) }

@ bytes_push_f32_be ( Vec u ) v f32 x → v { ( bytes_push_u32_be v # u32 ( f32_to_bits x ) ) }

@ bytes_push_f32_le ( Vec u ) v f32 x → v { ( bytes_push_u32_le v # u32 ( f32_to_bits x ) ) }

@ bytes_read_f64_be ( Vec u ) v i off → ?f {
    ?? ( bytes_read_u64_be v off ) { T b → @ ?f { T ( bits_to_f64 # i b ) } F → @ ?f { F 0.0 } }
}

@ bytes_read_f64_le ( Vec u ) v i off → ?f {
    ?? ( bytes_read_u64_le v off ) { T b → @ ?f { T ( bits_to_f64 # i b ) } F → @ ?f { F 0.0 } }
}

@ bytes_read_f32_be ( Vec u ) v i off → ?f32 {
    ?? ( bytes_read_u32_be v off ) { T b → @ ?f32 { T ( bits_to_f32 # i b ) } F → @ ?f32 { F # f32 0.0 } }
}

@ bytes_read_f32_le ( Vec u ) v i off → ?f32 {
    ?? ( bytes_read_u32_le v off ) { T b → @ ?f32 { T ( bits_to_f32 # i b ) } F → @ ?f32 { F # f32 0.0 } }
}
