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

// ── Half-precision (IEEE binary16) and bfloat16 bit conversion ──────
//
// Pure integer bit transport in both directions — no float round-trip,
// so subnormals, ±inf, NaN (payload included) and -0 survive exactly.
// The f32→narrow direction rounds to nearest, ties to even, exactly
// like hardware converts. These are the primitives under GGUF/ONNX
// tensor decoding, wire formats (CBOR half floats), and GPU data prep.
//
//   ( f16_bits_to_f32_bits h )   → i     widen, exact
//   ( f32_bits_to_f16_bits b )   → i     RNE narrow (overflow → ±inf)
//   ( bf16_bits_to_f32_bits h )  → i     widen, exact (<< 16)
//   ( f32_bits_to_bf16_bits b )  → i     RNE narrow, NaN kept NaN
//   ( f16_to_f h ) ( f_to_f16 x ) ( bf16_to_f h ) ( f_to_bf16 x )

// sign copied, exponent rebased 15 → 127, mantissa widened 10 → 23
// bits; subnormals normalised, inf/NaN mapped to their f32 forms.
@ f16_bits_to_f32_bits i h → i {
    : i sign << & >> h 15 1 31
    : i e & >> h 10 31
    : ~ i man & h 1023
    ? == e 0 {
        ? == man 0 { ^ sign } {}
        : ~ i ex 113
        ~ == & man 1024 0 {
            = man << man 1
            = ex - ex 1
        }
        = man & man 1023
        ^ | sign | << ex 23 << man 13
    } {}
    ? == e 31 { ^ | sign | 2139095040 << man 13 } {}
    ^ | sign | << + e 112 23 << man 13
}

// Round-to-nearest-even narrow. Exponent ≥ 31 after rebias → ±inf;
// tiny values denormalise (the mantissa round can carry back up into
// the exponent, which is exactly RNE's behaviour); NaN keeps its top
// payload bits and is forced non-zero so it cannot decay to inf.
@ f32_bits_to_f16_bits i b → i {
    : i sign & >> b 16 32768
    : i e & >> b 23 255
    : i man & b 8388607
    ? == e 255 {
        ? == man 0 { ^ | sign 31744 } {}
        : i pay >> man 13
        ^ | sign | 31744 ? == pay 0 512 pay
    } {}
    : i E - e 112
    ? >= E 31 { ^ | sign 31744 } {}
    ? <= E 0 {
        // subnormal target: shift the implicit-1 mantissa down
        ? < E -10 { ^ sign } {}
        : i M | man 8388608
        : i sh - 14 E
        : i v >> M sh
        : i rem & M - << 1 sh 1
        : i half << 1 - sh 1
        : ~ i out v
        ? | > rem half & == rem half == & v 1 1 { = out + v 1 } {}
        ^ | sign out
    } {}
    : ~ i v | << E 10 >> man 13
    : i rem & man 8191
    ? | > rem 4096 & == rem 4096 == & v 1 1 { = v + v 1 } {}
    ^ | sign v
}

@ bf16_bits_to_f32_bits i h → i { ^ << h 16 }

// RNE truncation of the low 16 mantissa bits; a NaN whose payload
// lives entirely in the dropped bits is pinned to a quiet NaN rather
// than rounding to inf.
@ f32_bits_to_bf16_bits i b → i {
    : i e & >> b 23 255
    : i man & b 8388607
    ? & == e 255 != man 0 {
        : i top >> b 16
        ^ ? == & top 127 0 | top 64 top
    } {}
    : i base >> b 16
    : i rem & b 65535
    ? | > rem 32768 & == rem 32768 == & base 1 1 { ^ + base 1 } {}
    ^ base
}

// f64-level conveniences (f32 is the exact carrier of every f16/bf16
// value, and f64 carries every f32, so these are lossless).
@ f16_to_f i h → f { ^ # f ( bits_to_f32 ( f16_bits_to_f32_bits h ) ) }

@ f_to_f16 f x → i { ^ ( f32_bits_to_f16_bits ( f32_to_bits # f32 x ) ) }

@ bf16_to_f i h → f { ^ # f ( bits_to_f32 ( bf16_bits_to_f32_bits h ) ) }

@ f_to_bf16 f x → i { ^ ( f32_bits_to_bf16_bits ( f32_to_bits # f32 x ) ) }
