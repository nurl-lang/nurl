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

// f16 at byte offset o of a block (little-endian).
inline @ __gg_ld_f16 ( Slice u ) P i o → f {
    ^ ( gg_f16_to_f ( slice_u16_le P o ) )
}

// Byte `o` of a block.
inline @ __gg_b ( Slice u ) P i o → i { ^ # i ( slice_at [u] P o ) }

// signed 8-bit read
inline @ __gg_i8 ( Slice u ) P i off → i {
    : i x # i ( slice_at [u] P off )
    ^ ? > x 127 - x 256 x
}

// Element `k` of an output window, as little-endian f32.
inline @ __gg_put ( Slice u ) W i k f v → v {
    ( slice_put_u32_le W * k 4 ( f32_to_bits # f32 v ) )
}

// ── K-quant helpers (super-blocks of 256) ───────────────────────────
//
// Q4_K / Q5_K pack eight 6-bit scale/min pairs into 12 bytes: the
// first four pairs sit in the low 6 bits of scales[0..3] (scale) and
// scales[4..7] (min); the last four take their low nibble from
// scales[8..11] and their high 2 bits from the top of scales[0..7].
// This is ggml's get_scale_min_k4, byte for byte.
inline @ __gg_k4_scale ( Slice u ) P i base i j → i {
    ? < j 4 { ^ & ( __gg_b P + base j ) 63 } {}
    ^ | & ( __gg_b P + base + j 4 ) 15 << >> ( __gg_b P + base - j 4 ) 6 4
}

inline @ __gg_k4_min ( Slice u ) P i base i j → i {
    ? < j 4 { ^ & ( __gg_b P + base + j 4 ) 63 } {}
    ^ | >> ( __gg_b P + base + j 4 ) 4 << >> ( __gg_b P + base j ) 6 4
}

// Dequantise a contiguous ELEMENT RANGE of tensor #idx — [first,
// first+count) — to little-endian f32. `first` and `count` must be
// multiples of the type's block size (they always are for whole rows:
// ggml guarantees dim0 is a block multiple). This is what lets a
// consumer touch one row of a multi-gigabyte embedding table without
// expanding the whole tensor: nurllama dequantises exactly the token's
// row per step.
@ gguf_dequant_range Gguf g i idx i first i count → !( Vec u ) String {
    ? | < first 0 < count 0 {
        ^ @ !( Vec u ) String { F ( string_from `gguf: negative dequant range` ) }
    } {}
    ? | < idx 0 >= idx ( gguf_n_tensors g ) {
        ^ @ !( Vec u ) String { F ( string_from `gguf: tensor index out of range` ) }
    } {}
    : ~ i gt -1
    : ~ i ne 0
    ?? ( vec_get [GgufTensor] ( gguf_tensors g ) idx ) {
        T t → {
            = gt . t gtype
            = ne . t nelems
        }
        F → {}
    }
    ? > + first count ne {
        ^ @ !( Vec u ) String { F ( string_from `gguf: dequant range runs past the tensor` ) }
    } {}
    : i blk ( gguf_type_blck gt )
    ? == blk 0 {
        : String m ( string_from `gguf: cannot dequantise tensor of unsized type ` )
        ( string_push_int m gt )
        ^ @ !( Vec u ) String { F m }
    } {}
    ? | != % first blk 0 != % count blk 0 {
        ^ @ !( Vec u ) String { F ( string_from `gguf: dequant range must be block-aligned` ) }
    } {}
    ^ ( __gg_dequant g idx first count )
}

// Dequantise the whole tensor.
@ gguf_dequant Gguf g i idx → !( Vec u ) String {
    ? | < idx 0 >= idx ( gguf_n_tensors g ) {
        ^ @ !( Vec u ) String { F ( string_from `gguf: tensor index out of range` ) }
    } {}
    : ~ i ne 0
    ?? ( vec_get [GgufTensor] ( gguf_tensors g ) idx ) {
        T t → { = ne . t nelems }
        F → {}
    }
    ^ ( __gg_dequant g idx 0 ne )
}

// The decoder. `first`/`count` are block-aligned element bounds,
// validated by the public entries above. Every block is read through a
// window of its own fixed size and written through one of 4·block bytes,
// so each index inside is provably in range: one check per block, not
// per byte.
@ __gg_dequant Gguf g i idx i first i count → !( Vec u ) String {
    : ~ i gt -1
    : ~ i nb -1
    : ~ ( Slice u ) T0 ( slice_empty [u] )
    ?? ( vec_get [GgufTensor] ( gguf_tensors g ) idx ) {
        T t → {
            = gt . t gtype
            = nb . t nbytes
            ? >= nb 0 { = T0 ( gguf_tensor_bytes g t ) } {}
        }
        F → {}
    }
    ? < nb 0 {
        : String m ( string_from `gguf: cannot dequantise tensor of unsized type ` )
        ( string_push_int m gt )
        ^ @ !( Vec u ) String { F m }
    } {}
    // Skip to the range's first block. Every layout below is a flat run
    // of fixed-size blocks, so the offset is exact.
    : i blk0 ( gguf_type_blck gt )
    : i esz ( gguf_type_size gt )
    : i ne count
    : ( Slice u ) P ( slice_window [u] T0 * / first blk0 esz * / count blk0 esz )

    // F32: verbatim copy.
    ? == gt 0 { ^ @ !( Vec u ) String { T ( slice_to_vec [u] P ) } } {}

    : ( Vec u ) outv ( vec_zeroed [u] * ne 4 )
    : ( Slice u ) O ( slice_from_vec [u] outv )

    // F64: narrow each element.
    ? == gt 28 {
        : ~ i k 0
        ~ < k ne {
            ( __gg_put O k ( bits_to_f64 ( slice_u64_le P * k 8 ) ) )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // F16: pure bit transport, no rounding anywhere.
    ? == gt 1 {
        : ~ i k 0
        ~ < k ne {
            ( slice_put_u32_le O * k 4 ( gg_f16_to_f32_bits ( slice_u16_le P * k 2 ) ) )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // BF16: f32 with the low 16 mantissa bits dropped — shift back up.
    ? == gt 30 {
        : ~ i k 0
        ~ < k ne {
            ( slice_put_u32_le O * k 4 << ( slice_u16_le P * k 2 ) 16 )
            = k + k 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q4_0
    ? == gt 2 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 18 18 )
            : ( Slice u ) W ( slice_window [u] O * b 128 128 )
            : f d ( __gg_ld_f16 B 0 )
            : ~ i j 0
            ~ < j 16 {
                : i x ( __gg_b B + 2 j )
                ( __gg_put W j * d # f - & x 15 8 )
                ( __gg_put W + j 16 * d # f - & >> x 4 15 8 )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q4_1
    ? == gt 3 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 20 20 )
            : ( Slice u ) W ( slice_window [u] O * b 128 128 )
            : f d ( __gg_ld_f16 B 0 )
            : f m ( __gg_ld_f16 B 2 )
            : ~ i j 0
            ~ < j 16 {
                : i x ( __gg_b B + 4 j )
                ( __gg_put W j + * d # f & x 15 m )
                ( __gg_put W + j 16 + * d # f & >> x 4 15 m )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q8_0
    ? == gt 8 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 34 34 )
            : ( Slice u ) W ( slice_window [u] O * b 128 128 )
            : f d ( __gg_ld_f16 B 0 )
            : ~ i j 0
            ~ < j 32 {
                ( __gg_put W j * d # f ( __gg_i8 B + 2 j ) )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q5_0 — 22-byte block: f16 d + 4 bytes of 5th bits + 16 nibble bytes
    ? == gt 6 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 22 22 )
            : ( Slice u ) W ( slice_window [u] O * b 128 128 )
            : f d ( __gg_ld_f16 B 0 )
            : i qh ( slice_u32_le B 2 )
            : ~ i j 0
            ~ < j 16 {
                : i x ( __gg_b B + 6 j )
                : i h0 << & >> qh j 1 4
                : i h1 << & >> qh + j 16 1 4
                ( __gg_put W j * d # f - | & x 15 h0 16 )
                ( __gg_put W + j 16 * d # f - | & >> x 4 15 h1 16 )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q5_1 — 24-byte block: f16 d + f16 m + 4 bytes of 5th bits + 16 nibbles
    ? == gt 7 {
        : i nblk / ne 32
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 24 24 )
            : ( Slice u ) W ( slice_window [u] O * b 128 128 )
            : f d ( __gg_ld_f16 B 0 )
            : f m ( __gg_ld_f16 B 2 )
            : i qh ( slice_u32_le B 4 )
            : ~ i j 0
            ~ < j 16 {
                : i x ( __gg_b B + 8 j )
                : i h0 << & >> qh j 1 4
                : i h1 << & >> qh + j 16 1 4
                ( __gg_put W j + * d # f | & x 15 h0 m )
                ( __gg_put W + j 16 + * d # f | & >> x 4 15 h1 m )
                = j + j 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q4_K — 144-byte super-block of 256: f16 d + f16 dmin + 12 scale
    // bytes + 128 nibble bytes. Eight 32-element sub-blocks, each with
    // its own 6-bit scale and min: value = d·scale·q − dmin·min.
    ? == gt 12 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 144 144 )
            : ( Slice u ) W ( slice_window [u] O * b 1024 1024 )
            : f d ( __gg_ld_f16 B 0 )
            : f dmin ( __gg_ld_f16 B 2 )
            : ~ i sub 0
            ~ < sub 8 {
                : f d1 * d # f ( __gg_k4_scale B 4 sub )
                : f m1 * dmin # f ( __gg_k4_min B 4 sub )
                // sub-blocks 0,2,4,6 read low nibbles; 1,3,5,7 the high
                // nibbles of the SAME 32 bytes
                : i qoff + 16 * / sub 2 32
                : b hi_nib == % sub 2 1
                : i ob * sub 32
                : ~ i l 0
                ~ < l 32 {
                    : i byte ( __gg_b B + qoff l )
                    : i q ? hi_nib >> byte 4 & byte 15
                    ( __gg_put W + ob l - * d1 # f q m1 )
                    = l + l 1
                }
                = sub + sub 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q5_K — 176-byte super-block: f16 d + f16 dmin + 12 scale bytes +
    // 32 bytes of 5th bits + 128 nibble bytes.
    ? == gt 13 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 176 176 )
            : ( Slice u ) W ( slice_window [u] O * b 1024 1024 )
            : f d ( __gg_ld_f16 B 0 )
            : f dmin ( __gg_ld_f16 B 2 )
            : ~ i sub 0
            ~ < sub 8 {
                : f d1 * d # f ( __gg_k4_scale B 4 sub )
                : f m1 * dmin # f ( __gg_k4_min B 4 sub )
                : i qoff + 48 * / sub 2 32
                : b hi_nib == % sub 2 1
                : i ob * sub 32
                : ~ i l 0
                ~ < l 32 {
                    : i byte ( __gg_b B + qoff l )
                    : i q ? hi_nib >> byte 4 & byte 15
                    : i hbit & >> ( __gg_b B + 16 l ) sub 1
                    ( __gg_put W + ob l - * d1 # f + q << hbit 4 m1 )
                    = l + l 1
                }
                = sub + sub 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    // Q6_K — 210-byte super-block: 128 low-nibble bytes + 64 bytes of
    // upper 2 bits + 16 int8 scales + f16 d. Sixteen 16-element groups
    // share one int8 scale: value = d·scale·(q − 32).
    ? == gt 14 {
        : i nblk / ne 256
        : ~ i b 0
        ~ < b nblk {
            : ( Slice u ) B ( slice_window [u] P * b 210 210 )
            : ( Slice u ) W ( slice_window [u] O * b 1024 1024 )
            : f d ( __gg_ld_f16 B 208 )
            : ~ i n 0
            ~ < n 2 {
                : i ql0 * n 64
                : i qh0 + 128 * n 32
                : i sc0 + 192 * n 8
                : ~ i l 0
                ~ < l 32 {
                    : i is / l 16
                    : i qhv ( __gg_b B + qh0 l )
                    : i b1 ( __gg_b B + ql0 l )
                    : i b2 ( __gg_b B + ql0 + l 32 )
                    : i q1 - | & b1 15 << & qhv 3 4 32
                    : i q2 - | & b2 15 << & >> qhv 2 3 4 32
                    : i q3 - | >> b1 4 << & >> qhv 4 3 4 32
                    : i q4 - | >> b2 4 << & >> qhv 6 3 4 32
                    : i s1 ( __gg_i8 B + sc0 is )
                    : i s2 ( __gg_i8 B + sc0 + is 2 )
                    : i s3 ( __gg_i8 B + sc0 + is 4 )
                    : i s4 ( __gg_i8 B + sc0 + is 6 )
                    : i ob + * n 128 l
                    ( __gg_put W ob * d * # f s1 # f q1 )
                    ( __gg_put W + ob 32 * d * # f s2 # f q2 )
                    ( __gg_put W + ob 64 * d * # f s3 # f q3 )
                    ( __gg_put W + ob 96 * d * # f s4 # f q4 )
                    = l + l 1
                }
                = n + n 1
            }
            = b + b 1
        }
        ^ @ !( Vec u ) String { T outv }
    } {}

    : String m ( string_from `gguf: dequantisation not implemented for type ` )
    ( string_push_str m ( gguf_type_name gt ) )
    ( string_push_str m ` (` )
    ( string_push_int m gt )
    ( string_push_str m `)` )
    ^ @ !( Vec u ) String { F m }
}

// Convenience: dequantise to host doubles (tests, small tensors).
@ gguf_dequant_f64 Gguf g i idx → !( Vec f ) String {
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
            ^ @ !( Vec f ) String { T out }
        }
        F e → { ^ @ !( Vec f ) String { F e } }
    }
}
