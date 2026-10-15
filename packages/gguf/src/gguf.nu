// packages/gguf/src/gguf.nu — a bulletproof GGUF container parser.
//
// GGUF is the ggml-ecosystem tensor container (llama.cpp, whisper.cpp,
// stable-diffusion.cpp): a little-endian header, typed metadata
// key/values, a tensor table, then an aligned data section. This module
// parses versions 2 and 3, mmap-backed, without ever loading tensor
// data into memory — tensor bytes are addressed lazily straight out of
// the mapping.
//
// Trust model: the file is UNTRUSTED input. Every count, length and
// offset is validated against the actual file size BEFORE any
// allocation or read depends on it; allocations are proportional to
// bytes actually consumed from the file, never to what a header merely
// claims. A malformed or truncated file is an error, never a crash, a
// hang, or an unbounded allocation.
//
//   ( gguf_open path )                → !Gguf String     mmap + parse
//   ( gguf_parse_bytes data )         → !Gguf String     parse a buffer
//                                       (the Gguf keeps `data`)
//   ( gguf_close g )                  → v   early release (optional)
//   ( gguf_kvs g ) ( gguf_tensors g ) → the metadata / tensor tables (borrowed)
//   an empty slot is a ?Gguf
//   ( gguf_n_kv g ) ( gguf_n_tensors g )            → i
//   ( gguf_find_kv g key )            → i   index, -1 when absent
//   ( gguf_kv_int_or g key def )      → i   any int/bool-typed KV
//   ( gguf_kv_f_or g key def )        → f   f32/f64-typed KV
//   ( gguf_kv_str_or g key def )      → s   BORROWED from g
//   ( gguf_find_tensor g name )       → i   index, -1 when absent
//   ( gguf_tensor_bytes g t )         → ( Slice u )  a tensor's bytes, a
//                                       view held to `g`
//   ( gguf_tensor_ptr g t )           → *u  raw: their address
//   ( gguf_type_name t ) ( gguf_type_blck t ) ( gguf_type_size t )
//
// Layout invariants enforced at parse time: magic, version ∈ {2,3},
// sane KV/tensor counts, in-bounds strings, no nested arrays, unique
// KV keys and tensor names, power-of-two alignment, dims ≥ 1 with
// overflow-checked element counts, aligned tensor offsets, and every
// sizable tensor fully inside the data section.
//
// A Gguf is a handle: every copy is the same open file, and the last
// owner unmaps it (or lets go of the buffer it was parsed from). Nothing
// here is released by hand.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/mmap.nu`
$ `stdlib/core/slice.nu`

// ── GGUF metadata value types (spec) ────────────────────────────────
: i GGUF_VT_U8 0
: i GGUF_VT_I8 1
: i GGUF_VT_U16 2
: i GGUF_VT_I16 3
: i GGUF_VT_U32 4
: i GGUF_VT_I32 5
: i GGUF_VT_F32 6
: i GGUF_VT_BOOL 7
: i GGUF_VT_STR 8
: i GGUF_VT_ARR 9
: i GGUF_VT_U64 10
: i GGUF_VT_I64 11
: i GGUF_VT_F64 12

// ── ggml tensor types ───────────────────────────────────────────────
// Name for a ggml type id; `?` for ids this parser has no name for.
@ gguf_type_name i t → s {
    ? == t 0 { ^ `F32` } {}
    ? == t 1 { ^ `F16` } {}
    ? == t 2 { ^ `Q4_0` } {}
    ? == t 3 { ^ `Q4_1` } {}
    ? == t 6 { ^ `Q5_0` } {}
    ? == t 7 { ^ `Q5_1` } {}
    ? == t 8 { ^ `Q8_0` } {}
    ? == t 9 { ^ `Q8_1` } {}
    ? == t 10 { ^ `Q2_K` } {}
    ? == t 11 { ^ `Q3_K` } {}
    ? == t 12 { ^ `Q4_K` } {}
    ? == t 13 { ^ `Q5_K` } {}
    ? == t 14 { ^ `Q6_K` } {}
    ? == t 15 { ^ `Q8_K` } {}
    ? == t 16 { ^ `IQ2_XXS` } {}
    ? == t 17 { ^ `IQ2_XS` } {}
    ? == t 18 { ^ `IQ3_XXS` } {}
    ? == t 19 { ^ `IQ1_S` } {}
    ? == t 20 { ^ `IQ4_NL` } {}
    ? == t 21 { ^ `IQ3_S` } {}
    ? == t 22 { ^ `IQ2_S` } {}
    ? == t 23 { ^ `IQ4_XS` } {}
    ? == t 24 { ^ `I8` } {}
    ? == t 25 { ^ `I16` } {}
    ? == t 26 { ^ `I32` } {}
    ? == t 27 { ^ `I64` } {}
    ? == t 28 { ^ `F64` } {}
    ? == t 29 { ^ `IQ1_M` } {}
    ? == t 30 { ^ `BF16` } {}
    ^ `?`
}

// Elements per quantisation block; 0 when this parser cannot size the
// type (unknown or not-yet-tabled id — such tensors are still listed,
// but their byte extent cannot be verified or dequantised).
@ gguf_type_blck i t → i {
    ? | | == t 0 == t 1 | == t 24 | == t 25 | == t 26 | == t 27 | == t 28 == t 30 { ^ 1 } {}
    ? | | == t 2 == t 3 | == t 6 | == t 7 | == t 8 | == t 9 == t 20 { ^ 32 } {}
    ? | | == t 10 == t 11 | == t 12 | == t 13 | == t 14 == t 15 { ^ 256 } {}
    ^ 0
}

// Bytes per quantisation block; 0 when unknown (pairs with gguf_type_blck).
@ gguf_type_size i t → i {
    ? == t 0 { ^ 4 } {}
    ? == t 1 { ^ 2 } {}
    ? == t 2 { ^ 18 } {}
    ? == t 3 { ^ 20 } {}
    ? == t 6 { ^ 22 } {}
    ? == t 7 { ^ 24 } {}
    ? == t 8 { ^ 34 } {}
    ? == t 9 { ^ 36 } {}
    ? == t 10 { ^ 84 } {}
    ? == t 11 { ^ 110 } {}
    ? == t 12 { ^ 144 } {}
    ? == t 13 { ^ 176 } {}
    ? == t 14 { ^ 210 } {}
    ? == t 15 { ^ 292 } {}
    ? == t 20 { ^ 18 } {}
    ? == t 24 { ^ 1 } {}
    ? == t 25 { ^ 2 } {}
    ? == t 26 { ^ 4 } {}
    ? == t 27 { ^ 8 } {}
    ? == t 28 { ^ 8 } {}
    ? == t 30 { ^ 2 } {}
    ^ 0
}

// ── parsed structures ───────────────────────────────────────────────

// One metadata key/value. `vt` discriminates which payload field holds
// the value: int family (u8..u64/i64/bool) → ival, f32/f64 → fval,
// string → sval, array → atype + one of ai/af/astr.
: GgufKv {
    String key
    i vt
    i ival
    f fval
    String sval
    i atype
    ( Vec i ) ai
    ( Vec f ) af
    ( Vec String ) astr
}

// One tensor-table entry. `offset` is RELATIVE to the data section
// (exactly as stored in the file); absolute bytes are reached through
// gguf_tensor_ptr. nbytes is -1 when the type cannot be sized.
: GgufTensor {
    String name
    i gtype
    i nd
    i d0
    i d1
    i d2
    i d3
    i nelems
    i offset
    i nbytes
}

: GgufImpl {
    i version
    i align
    ( Vec GgufKv ) kvs
    ( Vec GgufTensor ) tensors
    i data_off
    i data_size
    MappedFile file  // the bytes: a mapping, or a buffer read whole
}

// A Gguf is a handle on its state in an Arc (stdlib/std/arc.nu), frozen
// once parsed: every copy is the same open file, and the last owner lets
// go of the mapping.
: Gguf { ( Arc GgufImpl ) a }

@ Gguf_share Gguf h → Gguf { ^ @ Gguf { ( arc_clone [GgufImpl] . h a ) } }

@ Gguf_drop sink Gguf h → v {}

// A container with nothing in it: no metadata, no tensors, no bytes. What
// an engine record holds before its model file is opened.
@ gguf_empty → Gguf {
    ^ @ Gguf { ( arc_new [GgufImpl] @ GgufImpl { 0 0 ( vec_new [GgufKv] ) ( vec_new [GgufTensor] ) 0 0 ( mapped_of_bytes ( vec_new [u] ) ) } ) }
}

// ── bounded little-endian cursor over the mapping ───────────────────
// Every read checks the remaining byte budget first; the first
// out-of-bounds read latches `fail` and all subsequent reads return
// zero values, so a parse can run to a checkpoint and test `fail` once.
: GCur {
    ( Slice u ) p
    i n
    i off
    b fail
}

@ __gc_rem inout GCur c → i { ^ - . c n . c off }

// Overflow-safe budget check: compares k against (n - off), never
// forms off + k (a huge attacker-chosen k must not wrap negative).
@ __gc_need inout GCur c i k → b {
    ? . c fail { ^ F } {}
    ? | < k 0 > k - . c n . c off { = . c fail T ^ F } {}
    ^ T
}

@ __gc_u8 inout GCur c → i {
    ? ( __gc_need c 1 ) {} { ^ 0 }
    : i v # i ( slice_at [u] . c p . c off )
    = . c off + . c off 1
    ^ v
}

@ __gc_u16 inout GCur c → i {
    ? ( __gc_need c 2 ) {} { ^ 0 }
    : i o . c off
    = . c off + o 2
    ^ ( slice_u16_le . c p o )
}

@ __gc_u32 inout GCur c → i {
    ? ( __gc_need c 4 ) {} { ^ 0 }
    : i o . c off
    = . c off + o 4
    ^ ( slice_u32_le . c p o )
}

// Reads 8 bytes as i64 (two's-complement bit pattern). GGUF stores
// u64 here; a value ≥ 2^63 surfaces as negative and is rejected by
// the `< 0` validations at every use site.
@ __gc_u64 inout GCur c → i {
    : i lo ( __gc_u32 c )
    : i hi ( __gc_u32 c )
    ^ | lo << hi 32
}

// Length-prefixed GGUF string. `maxlen` caps the accepted length
// (keys/names are identifier-sized; general values are bounded by the
// remaining file bytes anyway). `forbid_nul` rejects embedded NULs —
// required for keys and tensor names which flow into C-string
// comparisons; value strings keep arbitrary bytes.
@ __gc_str inout GCur c i maxlen b forbid_nul → String {
    : i len ( __gc_u64 c )
    ? . c fail { ^ ( string_new ) } {}
    ? | < len 0 > len maxlen { = . c fail T ^ ( string_new ) } {}
    ? ( __gc_need c len ) {} { ^ ( string_new ) }
    : ( Slice u ) w ( slice_window [u] . c p . c off len )
    ? forbid_nul {
        : ~ i j 0
        ~ < j len {
            ? == ( slice_at [u] w j ) 0 { = . c fail T = j len } { = j + j 1 }
        }
    } {}
    ? . c fail { ^ ( string_new ) } {}
    : String out ( string_new )
    ( string_push_window out w 0 len )
    = . c off + . c off len
    ^ out
}

// ── typed value readers ─────────────────────────────────────────────

// Fixed byte size of a SCALAR value type; 0 for string/array/unknown.
@ __g_vt_size i vt → i {
    ? | == vt 0 == vt 1 { ^ 1 } {}
    ? | == vt 2 == vt 3 { ^ 2 } {}
    ? | == vt 4 | == vt 5 == vt 6 { ^ 4 } {}
    ? == vt 7 { ^ 1 } {}
    ? | == vt 10 | == vt 11 == vt 12 { ^ 8 } {}
    ^ 0
}

@ __g_read_int inout GCur c i vt → i {
    ? == vt 0 { ^ ( __gc_u8 c ) } {}
    ? == vt 1 {
        : i x ( __gc_u8 c )
        ^ ? > x 127 - x 256 x
    } {}
    ? == vt 2 { ^ ( __gc_u16 c ) } {}
    ? == vt 3 {
        : i x ( __gc_u16 c )
        ^ ? > x 32767 - x 65536 x
    } {}
    ? == vt 4 { ^ ( __gc_u32 c ) } {}
    ? == vt 5 {
        : i x ( __gc_u32 c )
        ^ ? > x 2147483647 - x 4294967296 x
    } {}
    ? == vt 7 {
        : i x ( __gc_u8 c )
        ^ ? != x 0 1 0
    } {}
    ? | == vt 10 == vt 11 { ^ ( __gc_u64 c ) } {}
    = . c fail T
    ^ 0
}

@ __g_read_f inout GCur c i vt → f {
    ? == vt 6 {
        : i bits ( __gc_u32 c )
        ^ # f ( bits_to_f32 bits )
    } {}
    ? == vt 12 { ^ ( bits_to_f64 ( __gc_u64 c ) ) } {}
    = . c fail T
    ^ 0.0
}

@ __g_int_vt i vt → b {
    ^ | | == vt 0 == vt 1 | == vt 2 | == vt 3 | == vt 4 | == vt 5 | == vt 7 | == vt 10 == vt 11
}

// ── KV / tensor entry parsers ───────────────────────────────────────
// Both always return a fully-initialised value (owned fields present
// even on failure) so error paths free exactly one shape.

@ __g_parse_kv inout GCur c → GgufKv {
    : String key ( __gc_str c 65536 T )
    : i vt ( __gc_u32 c )
    : ~ i ival 0
    : ~ f fval 0.0
    // string payload read in-place at declaration: a `= sval …`
    // reassignment would leak the initial empty String
    : String sval ? & ! . c fail == vt 8 ( __gc_str c ( __gc_rem c ) F ) ( string_new )
    : ~ i atype -1
    : ( Vec i ) ai ( vec_new [i] )
    : ( Vec f ) af ( vec_new [f] )
    : ( Vec String ) astr ( vec_new [String] )
    ? | . c fail == vt 8 {} {
        {
            ? == vt 9 {
                = atype ( __gc_u32 c )
                : i cnt ( __gc_u64 c )
                ? | . c fail < cnt 0 { = . c fail T } {
                    ? == atype 8 {
                        // string array: each element consumes ≥ 8 bytes
                        ? > cnt / ( __gc_rem c ) 8 { = . c fail T } {
                            : ~ i j 0
                            ~ & < j cnt ! . c fail {
                                ( vec_push [String] astr ( __gc_str c ( __gc_rem c ) F ) )
                                = j + j 1
                            }
                        }
                    } {
                        : i esz ( __g_vt_size atype )
                        ? == esz 0 { = . c fail T } {
                            ? > cnt / ( __gc_rem c ) esz { = . c fail T } {
                                : ~ i j 0
                                ~ & < j cnt ! . c fail {
                                    ? | == atype 6 == atype 12 {
                                        ( vec_push [f] af ( __g_read_f c atype ) )
                                    } {
                                        ( vec_push [i] ai ( __g_read_int c atype ) )
                                    }
                                    = j + j 1
                                }
                            }
                        }
                    }
                }
            } {
                ? | == vt 6 == vt 12 {
                    = fval ( __g_read_f c vt )
                } {
                    ? ( __g_int_vt vt ) { = ival ( __g_read_int c vt ) } { = . c fail T }
                }
            }
        }
    }
    ^ @ GgufKv { key vt ival fval sval atype ai af astr }
}

// Per-dimension cap 2^48 and running-product cap 2^48 keep
// nelems * max-block-bytes (292) far away from i64 overflow.
@ __g_parse_tensor inout GCur c → GgufTensor {
    : String name ( __gc_str c 4096 T )
    : i nd ( __gc_u32 c )
    : ~ i d0 1
    : ~ i d1 1
    : ~ i d2 1
    : ~ i d3 1
    ? | . c fail | < nd 1 > nd 4 { = . c fail T } {
        : ~ i j 0
        ~ & < j nd ! . c fail {
            : i d ( __gc_u64 c )
            ? | < d 1 > d 281474976710656 { = . c fail T } {
                ? == j 0 { = d0 d } {
                    ? == j 1 { = d1 d } {
                        ? == j 2 { = d2 d } { = d3 d }
                    }
                }
            }
            = j + j 1
        }
    }
    : i gt ( __gc_u32 c )
    : i rel ( __gc_u64 c )
    : ~ i ne 0
    ? . c fail {} {
        = ne d0
        ? > ne / 281474976710656 d1 { = . c fail T } { = ne * ne d1 }
    }
    ? . c fail {} {
        ? > ne / 281474976710656 d2 { = . c fail T } { = ne * ne d2 }
    }
    ? . c fail {} {
        ? > ne / 281474976710656 d3 { = . c fail T } { = ne * ne d3 }
    }
    ? < rel 0 { = . c fail T } {}
    : ~ i nb -1
    : i blk ( gguf_type_blck gt )
    ? & ! . c fail > blk 0 {
        ? != % d0 blk 0 { = . c fail T } {
            = nb * / ne blk ( gguf_type_size gt )
        }
    } {}
    ^ @ GgufTensor { name gt nd d0 d1 d2 d3 ne rel nb }
}

@ __g_errs s msg → !Gguf String {
    ^ @ !Gguf String { F ( string_from msg ) }
}

// ── the parser ──────────────────────────────────────────────────────
// Parses the metadata + tensor table of the bytes `file` holds; the Gguf
// keeps it for as long as the tensors are read.
@ __gguf_parse sink MappedFile file → !Gguf String {
    : ( Slice u ) p ( mapped_bytes file )
    : i n ( slice_len [u] p )
    ? < n 24 { ^ ( __g_errs `gguf: file too small to be GGUF (< 24 bytes)` ) } {}
    : ~ GCur c @ GCur { p n 0 F }
    : i m0 ( __gc_u8 c )
    : i m1 ( __gc_u8 c )
    : i m2 ( __gc_u8 c )
    : i m3 ( __gc_u8 c )
    ? | != m0 71 | != m1 71 | != m2 85 != m3 70 {
        ^ ( __g_errs `gguf: bad magic (not a GGUF file)` )
    } {}
    : i ver ( __gc_u32 c )
    ? == ver 1 {
        ^ ( __g_errs `gguf: version 1 is unsupported (legacy 32-bit layout); re-export as v2/v3` )
    } {}
    ? | < ver 2 > ver 3 {
        : String m ( string_from `gguf: unsupported version ` )
        ( string_push_int m ver )
        ^ @ !Gguf String { F m }
    } {}
    : i ntens ( __gc_u64 c )
    : i nkv ( __gc_u64 c )
    // Minimum encoded sizes (KV ≥ 12 bytes, tensor entry ≥ 32 bytes)
    // bound the counts by what the file could physically contain.
    ? | < nkv 0 > nkv / - n 24 12 {
        ^ ( __g_errs `gguf: absurd metadata count (corrupt or truncated file)` )
    } {}
    ? | < ntens 0 > ntens / - n 24 32 {
        ^ ( __g_errs `gguf: absurd tensor count (corrupt or truncated file)` )
    } {}

    // metadata key/values
    : ( Vec GgufKv ) kvs ( vec_new [GgufKv] )
    : ~ i k 0
    ~ & < k nkv ! . c fail {
        ( vec_push [GgufKv] kvs ( __g_parse_kv c ) )
        = k + k 1
    }
    ? . c fail {
        : String m ( string_from `gguf: corrupt or truncated metadata (kv #` )
        ( string_push_int m k )
        ( string_push_str m ` of ` )
        ( string_push_int m nkv )
        ( string_push_str m `)` )
        ^ @ !Gguf String { F m }
    } {}

    // unique keys (spec requirement; duplicates would make lookups lie)
    : ~ i dupk -1
    = k 0
    ~ < k ( vec_len [GgufKv] kvs ) {
        : ~ i j + k 1
        ~ < j ( vec_len [GgufKv] kvs ) {
            ?? ( vec_get [GgufKv] kvs k ) {
                T a → {
                    ?? ( vec_get [GgufKv] kvs j ) {
                        T b2 → {
                            ? ( string_eq . a key . b2 key ) { = dupk k } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            = j + j 1
        }
        = k + k 1
    }
    ? >= dupk 0 {
        : ~ String m ( string_from `gguf: duplicate metadata key ` )
        ?? ( vec_get [GgufKv] kvs dupk ) {
            T a → { ( string_push_str m ( string_data . a key ) ) }
            F → {}
        }
        ^ @ !Gguf String { F m }
    } {}

    // alignment (general.alignment, any integer type; default 32)
    : ~ i align 32
    = k 0
    ~ < k ( vec_len [GgufKv] kvs ) {
        ?? ( vec_get [GgufKv] kvs k ) {
            T a → {
                ? & != ( nurl_str_eq ( string_data . a key ) `general.alignment` ) 0 ( __g_int_vt . a vt ) {
                    = align . a ival
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? | | < align 1 > align 1048576 != & align - align 1 0 {
        ^ ( __g_errs `gguf: invalid general.alignment (must be a power of two, 1..1048576)` )
    } {}

    // tensor table
    : ( Vec GgufTensor ) ts ( vec_new [GgufTensor] )
    = k 0
    ~ & < k ntens ! . c fail {
        ( vec_push [GgufTensor] ts ( __g_parse_tensor c ) )
        = k + k 1
    }
    ? . c fail {
        : String m ( string_from `gguf: corrupt or truncated tensor table (entry #` )
        ( string_push_int m k )
        ( string_push_str m ` of ` )
        ( string_push_int m ntens )
        ( string_push_str m `)` )
        ^ @ !Gguf String { F m }
    } {}

    // unique tensor names
    : ~ i dupt -1
    = k 0
    ~ < k ( vec_len [GgufTensor] ts ) {
        : ~ i j + k 1
        ~ < j ( vec_len [GgufTensor] ts ) {
            ?? ( vec_get [GgufTensor] ts k ) {
                T a → {
                    ?? ( vec_get [GgufTensor] ts j ) {
                        T b2 → {
                            ? ( string_eq . a name . b2 name ) { = dupt k } {}
                        }
                        F → {}
                    }
                }
                F → {}
            }
            = j + j 1
        }
        = k + k 1
    }
    ? >= dupt 0 {
        : ~ String m ( string_from `gguf: duplicate tensor name ` )
        ?? ( vec_get [GgufTensor] ts dupt ) {
            T a → { ( string_push_str m ( string_data . a name ) ) }
            F → {}
        }
        ^ @ !Gguf String { F m }
    } {}

    // data section start: metadata end rounded up to the alignment
    : i meta_end . c off
    : ~ i doff meta_end
    : i rem % meta_end align
    ? != rem 0 { = doff + meta_end - align rem } {}
    ? > doff n {
        ? == ntens 0 { = doff n } {
            ^ ( __g_errs `gguf: truncated before the tensor data section` )
        }
    } {}
    : i dsize - n doff

    // every sizable tensor must sit aligned and fully inside the data
    // section (offset compared against dsize first — no overflow path)
    : ~ i badt -1
    = k 0
    ~ < k ( vec_len [GgufTensor] ts ) {
        ?? ( vec_get [GgufTensor] ts k ) {
            T t → {
                ? != % . t offset align 0 { = badt k } {}
                ? > . t offset dsize { = badt k } {}
                ? & >= . t nbytes 0 > . t nbytes - dsize . t offset { = badt k } {}
            }
            F → {}
        }
        = k + k 1
    }
    ? >= badt 0 {
        : ~ String m ( string_from `gguf: tensor ` )
        ?? ( vec_get [GgufTensor] ts badt ) {
            T t → {
                ( string_push_str m ( string_data . t name ) )
                ( string_push_str m ` lies outside the data section (offset ` )
                ( string_push_int m . t offset )
                ( string_push_str m `, bytes ` )
                ( string_push_int m . t nbytes )
                ( string_push_str m `, data size ` )
                ( string_push_int m dsize )
                ( string_push_str m `)` )
            }
            F → {}
        }
        ^ @ !Gguf String { F m }
    } {}

    : Gguf h @ Gguf { ( arc_new [GgufImpl] @ GgufImpl { ver align kvs ts doff dsize file } ) }
    ^ @ !Gguf String { T h }
}

// ── open / close ────────────────────────────────────────────────────

// mmap-backed open where the platform maps files (POSIX); elsewhere (wasm,
// win32) the whole file is read into a buffer the Gguf owns — correct
// everywhere, mmap-lazy where it matters.
@ gguf_open s path → !Gguf String {
    ?? ( file_map path ) {
        T m → { ^ ( __gguf_parse m ) }
        F _ → {
            : String msg ( string_from `gguf: cannot open ` )
            ( string_push_str msg path )
            ^ @ !Gguf String { F msg }
        }
    }
}

// Parse an in-memory GGUF image. The Gguf keeps `data` (its tensors are
// read out of it).
@ gguf_parse_bytes sink ( Vec u ) data → !Gguf String {
    ^ ( __gguf_parse ( mapped_of_bytes data ) )
}

// Let go of `g` now rather than at the end of its owner's scope; the last
// owner unmaps the file.
@ gguf_close sink Gguf g → v {}

// ── accessors ───────────────────────────────────────────────────────

@ gguf_version Gguf g__h → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ . g version
}

@ gguf_align Gguf g__h → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ . g align
}

@ gguf_n_kv Gguf g__h → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ ( vec_len [GgufKv] . g kvs )
}

// The metadata and tensor tables (borrowed: valid while the Gguf is).
@ gguf_kvs Gguf g__h → ( Vec GgufKv ) {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ . g kvs
}

@ gguf_tensors Gguf g__h → ( Vec GgufTensor ) {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ . g tensors
}

@ gguf_n_tensors Gguf g__h → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ ( vec_len [GgufTensor] . g tensors )
}

@ gguf_data_size Gguf g__h → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    ^ . g data_size
}

@ gguf_find_kv Gguf g__h s key → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : ~ i k 0
    : ~ i found -1
    ~ < k ( vec_len [GgufKv] . g kvs ) {
        ?? ( vec_get [GgufKv] . g kvs k ) {
            T a → {
                ? ( nurl_str_eq ( string_data . a key ) key ) { = found k = k ( vec_len [GgufKv] . g kvs ) } { = k + k 1 }
            }
            F → { = k + k 1 }
        }
    }
    ^ found
}

@ gguf_kv_int_or Gguf g__h s key i def → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : i idx ( gguf_find_kv g__h key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? ( __g_int_vt . a vt ) . a ival def }
        F → { ^ def }
    }
}

@ gguf_kv_f_or Gguf g__h s key f def → f {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : i idx ( gguf_find_kv g__h key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? | == . a vt 6 == . a vt 12 . a fval def }
        F → { ^ def }
    }
}

// BORROWED: the returned s points into g (or is `def`); valid while
// the Gguf is. Do not free.
@ gguf_kv_str_or Gguf g__h s key s def → s {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : i idx ( gguf_find_kv g__h key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? == . a vt 8 ( string_data . a sval ) def }
        F → { ^ def }
    }
}

@ gguf_find_tensor Gguf g__h s name → i {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : ~ i k 0
    : ~ i found -1
    ~ < k ( vec_len [GgufTensor] . g tensors ) {
        ?? ( vec_get [GgufTensor] . g tensors k ) {
            T t → {
                ? ( nurl_str_eq ( string_data . t name ) name ) { = found k = k ( vec_len [GgufTensor] . g tensors ) } { = k + k 1 }
            }
            F → { = k + k 1 }
        }
    }
    ^ found
}

// A tensor's bytes inside the mapping — t.nbytes of them, or everything
// to the end of the data section when its type cannot be sized — as a
// checked view that lives no longer than `g__h`.
@ gguf_tensor_bytes Gguf g__h GgufTensor t → ( Slice u ) {
    : GgufImpl g ( arc_get [GgufImpl] . g__h a )
    : i rel . t offset
    : i n ? >= . t nbytes 0 . t nbytes - . g data_size rel
    ^ ( slice_window [u] ( mapped_bytes . g file ) + . g data_off rel n )
}

// Their address, for a device upload. raw: the caller keeps `g__h` alive
// while it is used; the length is t.nbytes (when ≥ 0).
raw @ gguf_tensor_ptr Gguf g__h GgufTensor t → *u {
    ^ ( slice_data [u] ( gguf_tensor_bytes g__h t ) )
}
