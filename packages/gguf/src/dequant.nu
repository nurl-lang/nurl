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
// Supported source types: F32, F64, F16, BF16, Q4_0, Q4_1, Q5_0, Q5_1,
// Q8_0, and the K-quants Q4_K / Q5_K / Q6_K (the formats modern
// llama.cpp models actually ship in — a Q4_K_M file mixes Q4_K and
// Q6_K tensors).
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

// IEEE-754 binary16 → binary32 — the stdlib bit-transport primitive
// (stdlib/std/floatbits.nu), kept under the historical gg_ name for
// the package's public dequant API.
@ gg_f16_to_f32_bits i h → i {
    ^ ( f16_bits_to_f32_bits h )
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

// signed 8-bit read
@ __gg_i8 * u P i off → i {
    : i x # i . P off
    ^ ? > x 127 - x 256 x
}

// Q6_K produces its four quarters out of order, so it needs indexed
// stores rather than appends: the Vec is pre-sized once and written by
// element index.
@ __gg_set_f ( Vec u ) out i idx f v → v {
    : i bits ( f32_to_bits # f32 v )
    : i o * idx 4
    ( vec_set [u] out o # u & bits 255 )
    ( vec_set [u] out + o 1 # u & >> bits 8 255 )
    ( vec_set [u] out + o 2 # u & >> bits 16 255 )
    ( vec_set [u] out + o 3 # u & >> bits 24 255 )
}

// ── K-quant helpers (super-blocks of 256) ───────────────────────────
//
// Q4_K / Q5_K pack eight 6-bit scale/min pairs into 12 bytes: the
// first four pairs sit in the low 6 bits of scales[0..3] (scale) and
// scales[4..7] (min); the last four take their low nibble from
// scales[8..11] and their high 2 bits from the top of scales[0..7].
// This is ggml's get_scale_min_k4, byte for byte.
@ __gg_k4_scale * u P i base i j → i {
    ? < j 4 { ^ & # i . P + base j 63 } {}
    ^ | & # i . P + base + j 4 15 << >> # i . P + base - j 4 6 4
}

@ __gg_k4_min * u P i base i j → i {
    ? < j 4 { ^ & # i . P + base + j 4 63 } {}
    ^ | >> # i . P + base + j 4 4 << >> # i . P + base j 6 4
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
    // Q6_K writes its four quarters out of order (see below), so its
    // buffer is materialised up front and filled by index.
    ? == gt 14 {
        : ~ i z 0
        ~ < z * ne 4 {
            ( vec_push [u] out # u 0 )
            = z + z 1
        }
    } {}

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

    // Q5_0 — 22-byte block: f16 d + 4 bytes of 5th bits + 16 nibble bytes
    ? == gt 6 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : i base * b 22
            : f d ( __gg_ld_f16 P base )
            : i qh | | # i . P + base 2 << # i . P + base 3 8
            | << # i . P + base 4 16 << # i . P + base 5 24
            : ~ i j 0
            ~ < j 16 {
                : i lo & # i . P + base + 6 j 15
                : i hi >> # i . P + base + 6 j 4
                : i h0 << & >> qh j 1 4
                : i h1 << & >> qh + j 16 1 4
                ( __gg_push_f out * d # f - | lo h0 16 )
                = j + j 1
            }
            = j 0
            ~ < j 16 {
                : i hi & >> # i . P + base + 6 j 4 15
                : i h1 << & >> qh + j 16 1 4
                ( __gg_push_f out * d # f - | hi h1 16 )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q5_1 — 24-byte block: f16 d + f16 m + 4 bytes of 5th bits + 16 nibbles
    ? == gt 7 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : i base * b 24
            : f d ( __gg_ld_f16 P base )
            : f m ( __gg_ld_f16 P + base 2 )
            : i qh | | # i . P + base 4 << # i . P + base 5 8
            | << # i . P + base 6 16 << # i . P + base 7 24
            : ~ i j 0
            ~ < j 16 {
                : i lo & # i . P + base + 8 j 15
                : i h0 << & >> qh j 1 4
                ( __gg_push_f out + * d # f | lo h0 m )
                = j + j 1
            }
            = j 0
            ~ < j 16 {
                : i hi & >> # i . P + base + 8 j 4 15
                : i h1 << & >> qh + j 16 1 4
                ( __gg_push_f out + * d # f | hi h1 m )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q4_K — 144-byte super-block of 256: f16 d + f16 dmin + 12 scale
    // bytes + 128 nibble bytes. Eight 32-element sub-blocks, each with
    // its own 6-bit scale and min: value = d·scale·q − dmin·min.
    ? == gt 12 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : i base * b 144
            : f d ( __gg_ld_f16 P base )
            : f dmin ( __gg_ld_f16 P + base 2 )
            : i sbase + base 4
            : i qbase + base 16
            : ~ i sub 0
            ~ < sub 8 {
                : f d1 * d # f ( __gg_k4_scale P sbase sub )
                : f m1 * dmin # f ( __gg_k4_min P sbase sub )
                // sub-blocks 0,2,4,6 read low nibbles; 1,3,5,7 the high
                // nibbles of the SAME 32 bytes
                : i half / sub 2
                : i qoff + qbase * half 32
                : b hi_nib == % sub 2 1
                : ~ i l 0
                ~ < l 32 {
                    : i byte # i . P + qoff l
                    : i q ? hi_nib >> byte 4 & byte 15
                    ( __gg_push_f out - * d1 # f q m1 )
                    = l + l 1
                }
                = sub + sub 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q5_K — 176-byte super-block: f16 d + f16 dmin + 12 scale bytes +
    // 32 bytes of 5th bits + 128 nibble bytes.
    ? == gt 13 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : i base * b 176
            : f d ( __gg_ld_f16 P base )
            : f dmin ( __gg_ld_f16 P + base 2 )
            : i sbase + base 4
            : i hbase + base 16
            : i qbase + base 48
            : ~ i sub 0
            ~ < sub 8 {
                : f d1 * d # f ( __gg_k4_scale P sbase sub )
                : f m1 * dmin # f ( __gg_k4_min P sbase sub )
                : i half / sub 2
                : i qoff + qbase * half 32
                : b hi_nib == % sub 2 1
                : ~ i l 0
                ~ < l 32 {
                    : i byte # i . P + qoff l
                    : i q ? hi_nib >> byte 4 & byte 15
                    : i hbit & >> # i . P + hbase l sub 1
                    ( __gg_push_f out - * d1 # f + q << hbit 4 m1 )
                    = l + l 1
                }
                = sub + sub 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T out }
    } {}

    // Q6_K — 210-byte super-block: 128 low-nibble bytes + 64 bytes of
    // upper 2 bits + 16 int8 scales + f16 d. Sixteen 16-element groups
    // share one int8 scale: value = d·scale·(q − 32).
    ? == gt 14 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : i base * b 210
            : i qlb base
            : i qhb + base 128
            : i scb + base 192
            : f d ( __gg_ld_f16 P + base 208 )
            : ~ i n 0
            ~ < n 2 {
                : i ql0 + qlb * n 64
                : i qh0 + qhb * n 32
                : i sc0 + scb * n 8
                : ~ i l 0
                ~ < l 32 {
                    : i is / l 16
                    : i qhv # i . P + qh0 l
                    : i b1 # i . P + ql0 l
                    : i b2 # i . P + ql0 + l 32
                    : i q1 - | & b1 15 << & qhv 3 4 32
                    : i q2 - | & b2 15 << & >> qhv 2 3 4 32
                    : i q3 - | >> b1 4 << & >> qhv 4 3 4 32
                    : i q4 - | >> b2 4 << & >> qhv 6 3 4 32
                    : i s1 ( __gg_i8 P + sc0 is )
                    : i s2 ( __gg_i8 P + sc0 + is 2 )
                    : i s3 ( __gg_i8 P + sc0 + is 4 )
                    : i s4 ( __gg_i8 P + sc0 + is 6 )
                    : i obase + * b 256 + * n 128 l
                    ( __gg_set_f out obase * d * # f s1 # f q1 )
                    ( __gg_set_f out + obase 32 * d * # f s2 # f q2 )
                    ( __gg_set_f out + obase 64 * d * # f s3 # f q3 )
                    ( __gg_set_f out + obase 96 * d * # f s4 # f q4 )
                    = l + l 1
                }
                = n + n 1
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
