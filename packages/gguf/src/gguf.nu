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
//   ( gguf_open path )                → !*Gguf String    mmap + parse
//   ( gguf_parse_bytes data )         → !*Gguf String    parse a buffer
//                                       (BORROWS data — keep it alive
//                                        until gguf_close)
//   ( gguf_close g )                  → v                unmap + free
//   ( gguf_n_kv g ) ( gguf_n_tensors g )            → i
//   ( gguf_find_kv g key )            → i   index, -1 when absent
//   ( gguf_kv_int_or g key def )      → i   any int/bool-typed KV
//   ( gguf_kv_f_or g key def )        → f   f32/f64-typed KV
//   ( gguf_kv_str_or g key def )      → s   BORROWED from g
//   ( gguf_find_tensor g name )       → i   index, -1 when absent
//   ( gguf_tensor_ptr g t )           → *u  BORROWED tensor bytes
//   ( gguf_type_name t ) ( gguf_type_blck t ) ( gguf_type_size t )
//
// Layout invariants enforced at parse time: magic, version ∈ {2,3},
// sane KV/tensor counts, in-bounds strings, no nested arrays, unique
// KV keys and tensor names, power-of-two alignment, dims ≥ 1 with
// overflow-checked element counts, aligned tensor offsets, and every
// sizable tensor fully inside the data section.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`

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

: Gguf {
    i version
    i align
    ( Vec GgufKv ) kvs
    ( Vec GgufTensor ) tensors
    i data_off
    i data_size
    * u map
    i map_size
    b from_mmap
    ( Vec u ) buf
}

// ── bounded little-endian cursor over the raw mapping ───────────────
// Every read checks the remaining byte budget first; the first
// out-of-bounds read latches `fail` and all subsequent reads return
// zero values, so a parse can run to a checkpoint and test `fail` once.
: GCur {
    * u p
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
    : *u P . c p
    : i v # i . P . c off
    = . c off + . c off 1
    ^ v
}

@ __gc_u16 inout GCur c → i {
    ? ( __gc_need c 2 ) {} { ^ 0 }
    : *u P . c p
    : i o . c off
    = . c off + o 2
    ^ | # i . P o << # i . P + o 1 8
}

@ __gc_u32 inout GCur c → i {
    ? ( __gc_need c 4 ) {} { ^ 0 }
    : *u P . c p
    : i o . c off
    = . c off + o 4
    ^ | # i . P o | << # i . P + o 1 8 | << # i . P + o 2 16 << # i . P + o 3 24
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
    : *u P . c p
    ? forbid_nul {
        : ~ i j 0
        ~ < j len {
            ? == # i . P + . c off j 0 { = . c fail T = j len } { = j + j 1 }
        }
    } {}
    ? . c fail { ^ ( string_new ) } {}
    : *u src # *u + # i . c p . c off
    : String out ( string_from_bytes src len )
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

// ── owned-structure teardown ────────────────────────────────────────

@ __g_kv_drop GgufKv k → v {
    ( string_free . k key )
    ( string_free . k sval )
    ( vec_free [i] . k ai )
    ( vec_free [f] . k af )
    ( vec_free_with [String] . k astr \ String s → v { ( string_free s ) } )
}

@ __g_free_kvs ( Vec GgufKv ) v → v {
    ( vec_free_with [GgufKv] v \ GgufKv k → v { ( __g_kv_drop k ) } )
}

@ __g_free_tensors ( Vec GgufTensor ) v → v {
    ( vec_free_with [GgufTensor] v \ GgufTensor t → v { ( string_free . t name ) } )
}

@ __g_errs s msg → !*Gguf String {
    ^ @ !*Gguf String { F ( string_from msg ) }
}

// ── the parser ──────────────────────────────────────────────────────
// Parses the metadata + tensor table of the mapping [p, p+n) and
// returns a heap Gguf borrowing that mapping. Ownership flags are
// filled in by the callers (gguf_open / gguf_parse_bytes).
@ __gguf_parse * u p i n → !*Gguf String {
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
        ^ @ !*Gguf String { F m }
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
        ( __g_free_kvs kvs )
        : String m ( string_from `gguf: corrupt or truncated metadata (kv #` )
        ( string_push_int m k )
        ( string_push_str m ` of ` )
        ( string_push_int m nkv )
        ( string_push_str m `)` )
        ^ @ !*Gguf String { F m }
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
        ( __g_free_kvs kvs )
        ^ @ !*Gguf String { F m }
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
        ( __g_free_kvs kvs )
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
        ( __g_free_kvs kvs )
        ( __g_free_tensors ts )
        : String m ( string_from `gguf: corrupt or truncated tensor table (entry #` )
        ( string_push_int m k )
        ( string_push_str m ` of ` )
        ( string_push_int m ntens )
        ( string_push_str m `)` )
        ^ @ !*Gguf String { F m }
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
        ( __g_free_kvs kvs )
        ( __g_free_tensors ts )
        ^ @ !*Gguf String { F m }
    } {}

    // data section start: metadata end rounded up to the alignment
    : i meta_end . c off
    : ~ i doff meta_end
    : i rem % meta_end align
    ? != rem 0 { = doff + meta_end - align rem } {}
    ? > doff n {
        ? == ntens 0 { = doff n } {
            ( __g_free_kvs kvs )
            ( __g_free_tensors ts )
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
        ( __g_free_kvs kvs )
        ( __g_free_tensors ts )
        ^ @ !*Gguf String { F m }
    } {}

    : *Gguf g # *Gguf ( nurl_alloc Z Gguf )
    = . g version ver
    = . g align align
    = . g kvs kvs
    = . g tensors ts
    = . g data_off doff
    = . g data_size dsize
    = . g map p
    = . g map_size n
    = . g from_mmap F
    = . g buf ( vec_new [u] )
    ^ @ !*Gguf String { T g }
}

// ── open / close ────────────────────────────────────────────────────

// mmap-backed open (POSIX). Platforms without MAP_PRIVATE (wasm,
// win32) fall back to reading the whole file into an owned buffer —
// correct everywhere, mmap-lazy where it matters.
@ gguf_open s path → !*Gguf String {
    ? != ( posix_const `MAP_PRIVATE` ) -1 {
        : i32 fd ( open path # i32 ( posix_const `O_RDONLY` ) # i32 0 )
        ? < # i fd 0 {
            : String m ( string_from `gguf: cannot open ` )
            ( string_push_str m path )
            ^ @ !*Gguf String { F m }
        } {}
        : i sz ( lseek fd 0 # i32 2 )
        ? < sz 24 {
            : i _c ( close # i fd )
            ^ ( __g_errs `gguf: file too small to be GGUF (< 24 bytes)` )
        } {}
        : *u m ( mmap # *u 0 sz # i32 ( posix_const `PROT_READ` ) # i32 ( posix_const `MAP_PRIVATE` ) fd 0 )
        : i _c ( close # i fd )
        ? == # i m -1 { ^ ( __g_errs `gguf: mmap failed` ) } {}
        : !*Gguf String r ( __gguf_parse m sz )
        ?? r {
            T g → {
                = . g from_mmap T
                ^ @ !*Gguf String { T g }
            }
            F e → {
                : i32 _u ( munmap m sz )
                ^ @ !*Gguf String { F e }
            }
        }
    } {
        : !( Vec u ) IoErr r ( read_file_bytes path )
        ?? r {
            T data → {
                : !*Gguf String pr ( __gguf_parse ( vec_data [u] data ) ( vec_len [u] data ) )
                ?? pr {
                    T g → {
                        // adopt the file buffer: drop the placeholder
                        // empty vec first (g is manually managed — no
                        // auto-drop reaches its fields)
                        ( vec_free [u] . g buf )
                        = . g buf data
                        ^ @ !*Gguf String { T g }
                    }
                    F e → {
                        ( vec_free [u] data )
                        ^ @ !*Gguf String { F e }
                    }
                }
            }
            F _ → {
                : String m ( string_from `gguf: cannot read ` )
                ( string_push_str m path )
                ^ @ !*Gguf String { F m }
            }
        }
    }
}

// Parse an in-memory GGUF image. BORROWS `data` — the caller keeps the
// vec alive until gguf_close and frees it afterwards.
@ gguf_parse_bytes ( Vec u ) data → !*Gguf String {
    ^ ( __gguf_parse ( vec_data [u] data ) ( vec_len [u] data ) )
}

@ gguf_close * Gguf g → v {
    ( __g_free_kvs . g kvs )
    ( __g_free_tensors . g tensors )
    ? . g from_mmap {
        : i32 _u ( munmap . g map . g map_size )
    } {}
    ( vec_free [u] . g buf )
    ( nurl_free # s g )
}

// ── accessors ───────────────────────────────────────────────────────

@ gguf_version * Gguf g → i { ^ . g version }

@ gguf_align * Gguf g → i { ^ . g align }

@ gguf_n_kv * Gguf g → i { ^ ( vec_len [GgufKv] . g kvs ) }

@ gguf_n_tensors * Gguf g → i { ^ ( vec_len [GgufTensor] . g tensors ) }

@ gguf_data_size * Gguf g → i { ^ . g data_size }

@ gguf_find_kv * Gguf g s key → i {
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

@ gguf_kv_int_or * Gguf g s key i def → i {
    : i idx ( gguf_find_kv g key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? ( __g_int_vt . a vt ) . a ival def }
        F → { ^ def }
    }
}

@ gguf_kv_f_or * Gguf g s key f def → f {
    : i idx ( gguf_find_kv g key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? | == . a vt 6 == . a vt 12 . a fval def }
        F → { ^ def }
    }
}

// BORROWED: the returned s points into g (or is `def`); valid until
// gguf_close. Do not free.
@ gguf_kv_str_or * Gguf g s key s def → s {
    : i idx ( gguf_find_kv g key )
    ? < idx 0 { ^ def } {}
    ?? ( vec_get [GgufKv] . g kvs idx ) {
        T a → { ^ ? == . a vt 8 ( string_data . a sval ) def }
        F → { ^ def }
    }
}

@ gguf_find_tensor * Gguf g s name → i {
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

// BORROWED pointer to a tensor's first byte inside the mapping; valid
// until gguf_close. Length is t.nbytes (when ≥ 0).
@ gguf_tensor_ptr * Gguf g GgufTensor t → *u {
    ^ # *u + + # i . g map . g data_off . t offset
}
