// packages/gguf/src/dequant.nu — host-side scalar dequantisation.
//
// Reference implementation of the ggml block-quant decodings, pure
// NURL, no GPU dependency: this is the CPU decode path AND the golden
// oracle a GPU dequant kernel is verified against. Output is the
// upload-ready canonical form — a ( Vec u ) of little-endian IEEE-754
// f32 values, one per tensor element, in storage order.
//
//   ( gg_f16_to_f32_bits h )     → i    IEEE half → f32 bit pattern
//   ( gg_f16_to_f )              → f    IEEE half → double
//   ( gguf_dequant g idx )       → !( Vec u ) String   f32-LE buffer
//   ( gguf_dequant_f64 g idx )   → !( Vec f ) String   convenience
//
// Supported source types: F32, F64, F16, BF16, Q4_0, Q4_1, Q8_0.
// Anything else is a clean error naming the type — never a wrong
// answer. Layouts follow ggml exactly:
//   Q4_0: 18-byte block = f16 scale d + 16 nibble bytes; elements
//         0..15 are the LOW nibbles, 16..31 the HIGH nibbles; value
//         = d * (q - 8).
//   Q4_1: 20-byte block = f16 d + f16 min m + 16 nibble bytes;
//         value = d * q + m (same nibble order).
//   Q8_0: 34-byte block = f16 d + 32 signed bytes; value = d * q.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `gguf.nu`

// IEEE-754 binary16 → binary32, pure integer bit transport: sign
// copied, exponent rebased 15 → 127, mantissa widened 10 → 23 bits.
// Subnormals are normalised; ±inf and NaN map to their f32 forms.
@ gg_f16_to_f32_bits i h → i {
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

@ gg_f16_to_f i h → f {
    ^ # f ( bits_to_f32 ( gg_f16_to_f32_bits h ) )
}

// f16 at byte offset o of pointer P (little-endian).
@ __gg_ld_f16 * u P i o → f {
    ^ ( gg_f16_to_f | # i . P o << # i . P + o 1 8 )
}

@ __gg_push_f ( Vec u ) out f v → v {
    ( bytes_push_u32_le out # u32 ( f32_to_bits # f32 v ) )
}

// Dequantise tensor #idx of g to little-endian f32 (4 bytes per
// element, storage order). Allocation is nelems * 4 — bounded because
// nelems was range-proven against the file at parse time.
@ gguf_dequant * Gguf g i idx → !( Vec u ) String {
    ? | < idx 0 >= idx ( gguf_n_tensors g ) {
        ^ @ !( Vec u ) String { F ( string_from `gguf: tensor index out of range` ) }
    } {}
    : ~ i gt -1
    : ~ i ne 0
    : ~ i nb -1
    : ~ i addr 0
    ?? ( vec_get [GgufTensor] . g tensors idx ) {
        T t → {
            = gt . t gtype
            = ne . t nelems
            = nb . t nbytes
            = addr # i ( gguf_tensor_ptr g t )
        }
        F → {}
    }
    ? < nb 0 {
        : String m ( string_from `gguf: cannot dequantise tensor of unsized type ` )
        ( string_push_int m gt )
        ^ @ !( Vec u ) String { F m }
    } {}
    : *u P # *u addr
    : ( Vec u ) out ( vec_with_cap [u] * ne 4 )

    // F32: verbatim copy.
    ? == gt 0 {
        ( bytes_extend_raw out # s P nb )
        ^ @ !( Vec u ) String { T out }
    } {}

    // F64: narrow each element.
    ? == gt 28 {
        : ~ i k 0
        ~ < k ne {
            : i o * k 8
            : ~ i b8 0
            : ~ i j 8
            ~ > j 0 {
                = j - j 1
                = b8 | << b8 8 # i . P + o j
            }
            ( __gg_push_f out ( bits_to_f64 b8 ) )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // F16: pure bit transport, no rounding anywhere.
    ? == gt 1 {
        : ~ i k 0
        ~ < k ne {
            : i o * k 2
            : i h | # i . P o << # i . P + o 1 8
            ( bytes_push_u32_le out # u32 ( gg_f16_to_f32_bits h ) )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // BF16: f32 with the low 16 mantissa bits dropped — shift back up.
    ? == gt 30 {
        : ~ i k 0
        ~ < k ne {
            : i o * k 2
            : i h | # i . P o << # i . P + o 1 8
            ( bytes_push_u32_le out # u32 << h 16 )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q4_0
    ? == gt 2 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : i base * b 18
            : f d ( __gg_ld_f16 P base )
            : ~ i j 0
            ~ < j 16 {
                : i q & # i . P + base + 2 j 15
                ( __gg_push_f out * d # f - q 8 )
                = j + j 1
            }
            = j 0
            ~ < j 16 {
                : i q & >> # i . P + base + 2 j 4 15
                ( __gg_push_f out * d # f - q 8 )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q4_1
    ? == gt 3 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : i base * b 20
            : f d ( __gg_ld_f16 P base )
            : f m ( __gg_ld_f16 P + base 2 )
            : ~ i j 0
            ~ < j 16 {
                : i q & # i . P + base + 4 j 15
                ( __gg_push_f out + * d # f q m )
                = j + j 1
            }
            = j 0
            ~ < j 16 {
                : i q & >> # i . P + base + 4 j 4 15
                ( __gg_push_f out + * d # f q m )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q8_0
    ? == gt 8 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : i base * b 34
            : f d ( __gg_ld_f16 P base )
            : ~ i j 0
            ~ < j 32 {
                : ~ i q # i . P + base + 2 j
                ? > q 127 { = q - q 256 } {}
                ( __gg_push_f out * d # f q )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    ( vec_free [u] out )
    : String m ( string_from `gguf: dequantisation not implemented for type ` )
    ( string_push_str m ( gguf_type_name gt ) )
    ( string_push_str m ` (` )
    ( string_push_int m gt )
    ( string_push_str m `)` )
    ^ @ !( Vec u ) String { F m }
}

// Convenience: dequantise to host doubles (tests, small tensors).
@ gguf_dequant_f64 * Gguf g i idx → !( Vec f ) String {
    : !( Vec u ) String r ( gguf_dequant g idx )
    ?? r {
        T raw → {
            : i n / ( vec_len [u] raw ) 4
            : ( Vec f ) out ( vec_with_cap [f] n )
            : ~ i k 0
            ~ < k n {
                ?? ( bytes_read_f32_le raw * k 4 ) {
                    T x → { ( vec_push [f] out # f x ) }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [u] raw )
            ^ @ !( Vec f ) String { T out }
        }
        F e → { ^ @ !( Vec f ) String { F e } }
    }
}
