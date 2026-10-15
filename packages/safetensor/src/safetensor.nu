// packages/safetensor/src/safetensor.nu — the safetensors container, parsed
// as HOSTILE input.
//
// The format is deliberately small:
//
//     u64 LE header_len
//     header_len bytes of JSON   { "name": {dtype, shape, data_offsets:[a,b]}, … }
//     the tensor bytes           (a and b are offsets INTO this region)
//
// which means a file that lies about its offsets is the whole attack surface.
// So: header_len is checked against the real file size before the JSON is even
// looked at, every tensor's [a,b) is checked to lie inside the data region,
// b − a must equal what dtype × shape actually needs, and the element count is
// accumulated with an overflow check rather than multiplied and hoped for.
// Nothing is allocated on the strength of a number the file supplied.
//
// mmap-backed and lazy, like gguf: the header is parsed up front, tensor bytes
// are read straight out of the mapping (stdlib/std/mmap.nu), so inspecting a
// multi-GB model costs no RAM. Every read is a checked slice of it.
//
//   ( st_open path )                → !St String
//   ( st_parse_bytes data )         → !St String   (keeps `data`)
//   ( st_n_tensors s )              → i
//   ( st_tensors s )                → ( Vec StTensor )   (borrowed)
//   ( st_find_tensor s name )       → i        (-1 = absent)
//   ( st_tensor_bytes s t )         → ( Slice u )   the tensor's bytes, a
//                                     view that lives no longer than `s`
//   ( st_tensor_ptr s t )           → *u       raw: their address, for a
//                                     device upload that keeps `s` alive
//   ( st_dequant s idx )            → !( Vec u ) String   — f32 bytes
//   ( st_dequant_range s idx first count ) → !( Vec u ) String
//   ( st_close s )                  → v        early release (optional)
//   an empty slot is a ?St
//
// An St is a handle: every copy is the same open file, and the last owner
// unmaps it (or lets go of the buffer it was parsed from). Nothing here is
// released by hand.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/mmap.nu`

// ── dtypes ──────────────────────────────────────────────────────────
// Our own codes; the file spells them as strings.
: i ST_F64 0
: i ST_F32 1
: i ST_F16 2
: i ST_BF16 3
: i ST_I64 4
: i ST_I32 5
: i ST_I16 6
: i ST_I8 7
: i ST_U8 8
: i ST_BOOL 9
: i ST_U16 10
: i ST_U32 11
: i ST_U64 12

@ st_dtype_of s name → i {
    ? ( nurl_str_eq name `F64` ) { ^ ST_F64 } {}
    ? ( nurl_str_eq name `F32` ) { ^ ST_F32 } {}
    ? ( nurl_str_eq name `F16` ) { ^ ST_F16 } {}
    ? ( nurl_str_eq name `BF16` ) { ^ ST_BF16 } {}
    ? ( nurl_str_eq name `I64` ) { ^ ST_I64 } {}
    ? ( nurl_str_eq name `I32` ) { ^ ST_I32 } {}
    ? ( nurl_str_eq name `I16` ) { ^ ST_I16 } {}
    ? ( nurl_str_eq name `I8` ) { ^ ST_I8 } {}
    ? ( nurl_str_eq name `U8` ) { ^ ST_U8 } {}
    ? ( nurl_str_eq name `BOOL` ) { ^ ST_BOOL } {}
    ? ( nurl_str_eq name `U16` ) { ^ ST_U16 } {}
    ? ( nurl_str_eq name `U32` ) { ^ ST_U32 } {}
    ? ( nurl_str_eq name `U64` ) { ^ ST_U64 } {}
    ^ -1
}

@ st_dtype_name i t → s {
    ? == t ST_F64 { ^ `F64` } {}
    ? == t ST_F32 { ^ `F32` } {}
    ? == t ST_F16 { ^ `F16` } {}
    ? == t ST_BF16 { ^ `BF16` } {}
    ? == t ST_I64 { ^ `I64` } {}
    ? == t ST_I32 { ^ `I32` } {}
    ? == t ST_I16 { ^ `I16` } {}
    ? == t ST_I8 { ^ `I8` } {}
    ? == t ST_U8 { ^ `U8` } {}
    ? == t ST_BOOL { ^ `BOOL` } {}
    ? == t ST_U16 { ^ `U16` } {}
    ? == t ST_U32 { ^ `U32` } {}
    ? == t ST_U64 { ^ `U64` } {}
    ^ `?`
}

// Bytes per element. Every dtype is fixed-width — there is no block
// quantisation in safetensors, which is why a row range is always exact.
@ st_dtype_size i t → i {
    ? | | == t ST_F64 == t ST_I64 == t ST_U64 { ^ 8 } {}
    ? | | == t ST_F32 == t ST_I32 == t ST_U32 { ^ 4 } {}
    ? | | | == t ST_F16 == t ST_BF16 == t ST_I16 == t ST_U16 { ^ 2 } {}
    ? | | == t ST_I8 == t ST_U8 == t ST_BOOL { ^ 1 } {}
    ^ 0
}

: StTensor {
    String name
    i dtype
    i nd
    i d0
    i d1
    i d2
    i d3
    i nelems
    i offset  // absolute offset into the FILE
    i nbytes
}

: StImpl {
    MappedFile file  // the bytes: a mapping, or a buffer read whole
    ( Vec StTensor ) tensors
    i data_off  // absolute offset of the tensor-data region
    i data_size
}

// An St is a handle on its state in an Arc (stdlib/std/arc.nu), frozen once
// parsed: every copy is the same open file, and the last owner lets go of
// the mapping.
: St { ( Arc StImpl ) a }

@ St_share St h → St { ^ @ St { ( arc_clone [StImpl] . h a ) } }

@ St_drop sink St h → v {}

@ __st_errs s msg → !St String {
    ^ @ !St String { F ( string_from msg ) }
}

@ __st_err_vec s msg → !( Vec u ) String {
    ^ @ !( Vec u ) String { F ( string_from msg ) }
}

// ── parse ───────────────────────────────────────────────────────────

// Read the u64 header length from the first 8 bytes. Little-endian, and a
// value ≥ 2^63 surfaces as negative — which the caller rejects.
@ __st_hdr_len ( Slice u ) p → i {
    : ~ i v 0
    : ~ i k 7
    ~ >= k 0 {
        = v | << v 8 # i ( slice_at [u] p k )
        = k - k 1
    }
    ^ v
}

// One shape dimension out of the JSON array, or -1 when it is not a
// non-negative integer.
@ __st_dim Json arr i idx → i {
    ?? ( json_arr_get arr idx ) {
        T d → {
            ? ( json_is_num d ) {} { ^ -1 }
            : i v ( json_as_int d )
            ? < v 0 { ^ -1 } {}
            ^ v
        }
        F → { ^ -1 }
    }
}

// Element count, accumulated with an overflow check at every step. A shape
// like [2^40, 2^40] must be an error, not a wrapped-around small number that
// later sizes an allocation.
@ __st_nelems i d0 i d1 i d2 i d3 i nd → i {
    : ~ i n 1
    : ~ i k 0
    ~ < k nd {
        : i d ? == k 0 d0 ? == k 1 d1 ? == k 2 d2 d3
        ? < d 0 { ^ -1 } {}
        ? == d 0 { ^ 0 } {}
        // n * d must stay inside i64: check BEFORE multiplying.
        ? > n / 9223372036854775807 d { ^ -1 } {}
        = n * n d
        = k + k 1
    }
    ^ n
}

// Parse the container `file` holds; the St keeps it for as long as the
// tensors are read.
@ __st_parse sink MappedFile file → !St String {
    : ( Slice u ) p ( mapped_bytes file )
    : i n ( slice_len [u] p )
    ? < n 8 { ^ ( __st_errs `safetensor: file too small (< 8 bytes)` ) } {}
    : i hlen ( __st_hdr_len p )
    // hlen is attacker-chosen: it must be positive, and 8 + hlen must fit in
    // the file. Compare against the remainder — never form 8 + hlen, which a
    // huge hlen would wrap.
    ? | < hlen 2 > hlen - n 8 {
        ^ ( __st_errs `safetensor: header length does not fit in the file` )
    } {}
    : i data_off + 8 hlen
    : i data_size - n data_off

    // The header is JSON, and json_parse takes a C string — so it is copied
    // out of the mapping with a NUL. It is the one thing we must copy: the
    // tensor bytes stay in the mapping.
    : String hdr ( string_new )
    ( string_push_window hdr p 8 hlen )
    : !Json JsonError jr ( json_parse ( string_data hdr ) )
    : ~ Json root ( json_null )
    ?? jr {
        T j → { = root j }
        F e → {
            : String m ( json_format_error e )
            : String msg ( string_from `safetensor: header is not valid JSON: ` )
            ( string_push_str msg ( string_data m ) )
            ^ @ !St String { F msg }
        }
    }
    ? ( json_is_obj root ) {} {
        ^ ( __st_errs `safetensor: header JSON is not an object` )
    }

    : ( Vec StTensor ) tensors ( vec_new [StTensor] )
    : ( Vec String ) keys ( json_obj_keys root )
    : ~ b ok T
    : ~ String err ( string_new )
    : ~ i ki 0
    ~ & ok < ki ( vec_len [String] keys ) {
        ?? ( vec_get [String] keys ki ) {
            T kn → {
                : s key ( string_data kn )
                // `__metadata__` is free-form and carries no tensor.
                ? ( nurl_str_eq key `__metadata__` ) {} {
                    ?? ( json_obj_get root key ) {
                        T e → {
                            ? ( json_is_obj e ) {} {
                                = ok F
                                = err ( string_from `safetensor: tensor entry is not an object` )
                            }
                            ? ok {
                                : ~ i dt -1
                                ?? ( json_obj_get e `dtype` ) {
                                    T d → { ? ( json_is_str d ) { = dt ( st_dtype_of ( json_as_str d ) ) } {} }
                                    F → {}
                                }
                                ? < dt 0 {
                                    = ok F
                                    = err ( string_from `safetensor: unknown or missing dtype for tensor '` )
                                    ( string_push_str err key )
                                    ( string_push_str err `'` )
                                } {}
                                : ~ i nd 0
                                : ~ i d0 1
                                : ~ i d1 1
                                : ~ i d2 1
                                : ~ i d3 1
                                ? ok {
                                    ?? ( json_obj_get e `shape` ) {
                                        T sh → {
                                            ? ( json_is_arr sh ) {} {
                                                = ok F
                                                = err ( string_from `safetensor: shape is not an array` )
                                            }
                                            ? ok {
                                                = nd ( json_arr_len sh )
                                                ? > nd 4 {
                                                    = ok F
                                                    = err ( string_from `safetensor: more than 4 dimensions` )
                                                } {}
                                                ? ok {
                                                    ? > nd 0 { = d0 ( __st_dim sh 0 ) } {}
                                                    ? > nd 1 { = d1 ( __st_dim sh 1 ) } {}
                                                    ? > nd 2 { = d2 ( __st_dim sh 2 ) } {}
                                                    ? > nd 3 { = d3 ( __st_dim sh 3 ) } {}
                                                    ? | | | < d0 0 < d1 0 < d2 0 < d3 0 {
                                                        = ok F
                                                        = err ( string_from `safetensor: shape dimension is not a non-negative integer` )
                                                    } {}
                                                } {}
                                            } {}
                                        }
                                        F → {
                                            = ok F
                                            = err ( string_from `safetensor: tensor has no shape` )
                                        }
                                    }
                                } {}
                                : ~ i a -1
                                : ~ i b -1
                                ? ok {
                                    ?? ( json_obj_get e `data_offsets` ) {
                                        T off → {
                                            ? & ( json_is_arr off ) == 2 ( json_arr_len off ) {
                                                = a ( __st_dim off 0 )
                                                = b ( __st_dim off 1 )
                                            } {
                                                = ok F
                                                = err ( string_from `safetensor: data_offsets is not a 2-element array` )
                                            }
                                        }
                                        F → {
                                            = ok F
                                            = err ( string_from `safetensor: tensor has no data_offsets` )
                                        }
                                    }
                                } {}
                                ? ok {
                                    : i ne ( __st_nelems d0 d1 d2 d3 nd )
                                    : i esz ( st_dtype_size dt )
                                    // nbytes: overflow-checked, like the shape.
                                    : ~ i nb -1
                                    ? & >= ne 0 > esz 0 {
                                        ? <= ne / 9223372036854775807 esz { = nb * ne esz } {}
                                    } {}
                                    // Every offset must land inside the DATA region — the
                                    // region computed from the real file size, not from
                                    // anything the header claims — and the extent must be
                                    // exactly what the dtype and shape need. This is the
                                    // check that turns a lying header into a clean error.
                                    ? | | | | | < ne 0 < nb 0 < a 0 < b a > b data_size != - b a nb {
                                        = ok F
                                        = err ( string_from `safetensor: tensor '` )
                                        ( string_push_str err key )
                                        ( string_push_str err `' has data_offsets outside the file or the wrong extent for its dtype/shape` )
                                    } {
                                        ( vec_push [StTensor] tensors @ StTensor {
                                            ( string_from key ) dt nd d0 d1 d2 d3 ne + data_off a nb } )
                                    }
                                } {}
                            } {}
                        }
                        F → {}
                    }
                }
            }
            F → {}
        }
        = ki + ki 1
    }
    ? ok {} { ^ @ !St String { F err } }
    ^ @ !St String { T @ St { ( arc_new [StImpl] @ StImpl { file tensors data_off data_size } ) } }
}

// ── open / close ────────────────────────────────────────────────────

// mmap-backed where the platform has it (POSIX), a whole-file read where it
// does not (wasm, win32) — correct everywhere, lazy where it matters.
@ st_open s path → !St String {
    ?? ( file_map path ) {
        T m → { ^ ( __st_parse m ) }
        F _ → {
            : String msg ( string_from `safetensor: cannot open ` )
            ( string_push_str msg path )
            ^ @ !St String { F msg }
        }
    }
}

// Parse an in-memory image. The St keeps `data` (its tensors are read out
// of it).
@ st_parse_bytes sink ( Vec u ) data → !St String {
    ^ ( __st_parse ( mapped_of_bytes data ) )
}

// Let go of `s` now rather than at the end of its owner's scope; the last
// owner unmaps the file.
@ st_close sink St s → v {}

// ── accessors ───────────────────────────────────────────────────────

@ st_n_tensors St h → i {
    ^ ( vec_len [StTensor] . ( arc_get [StImpl] . h a ) tensors )
}

// The tensor table (borrowed: valid while the St is).
@ st_tensors St h → ( Vec StTensor ) {
    ^ . ( arc_get [StImpl] . h a ) tensors
}

@ st_data_size St h → i {
    ^ . ( arc_get [StImpl] . h a ) data_size
}

@ st_find_tensor St h s name → i {
    : StImpl s ( arc_get [StImpl] . h a )
    : ~ i k 0
    : i n ( vec_len [StTensor] . s tensors )
    ~ < k n {
        ?? ( vec_get [StTensor] . s tensors k ) {
            T t → { ? ( nurl_str_eq ( string_data . t name ) name ) { ^ k } {} }
            F → {}
        }
        = k + k 1
    }
    ^ -1
}

// The tensor's bytes, straight out of the mapping: a checked view that
// lives no longer than `h` (the borrow checker holds it to that). A tensor
// of another St that does not fit this one panics rather than reading
// past it.
@ st_tensor_bytes St h StTensor t → ( Slice u ) {
    ^ ( slice_window [u] ( mapped_bytes . ( arc_get [StImpl] . h a ) file ) . t offset . t nbytes )
}

// Their address, for a hand-off that takes a pointer (a device upload).
// raw: the caller keeps `h` (any copy of it) alive while it is used.
raw @ st_tensor_ptr St h StTensor t → *u {
    ^ ( slice_data [u] ( st_tensor_bytes h t ) )
}

// ── dequantisation to f32 ───────────────────────────────────────────
// Every safetensors dtype is fixed-width, so an element range is exact — no
// block alignment to respect (which is what makes this simpler than gguf).

// Little-endian scalar reads out of a view of the mapping: one bounds
// check per word (stdlib/core/slice.nu).
@ __st_u16 ( Slice u ) P i o → i { ^ ( slice_u16_le P o ) }

@ _st_u32 ( Slice u ) P i o → i { ^ ( slice_u32_le P o ) }

@ __st_u64 ( Slice u ) P i o → i { ^ ( slice_u64_le P o ) }

// Sign-extending readers: the raw word is unsigned, the dtype is not.
@ __st_i8 ( Slice u ) P i o → i {
    : i v # i ( slice_at [u] P o )
    ^ ? > v 127 - v 256 v
}

@ __st_i16 ( Slice u ) P i o → i {
    : i v ( __st_u16 P o )
    ^ ? > v 32767 - v 65536 v
}

@ __st_i32 ( Slice u ) P i o → i {
    : i v ( _st_u32 P o )
    ^ ? > v 2147483647 - v 4294967296 v
}

// One element of a tensor, as f32. Every dtype widens to f32 here — an f64
// loses precision (by construction: the device runs f32) and an integer
// tensor becomes its numeric value.
@ __st_read_f ( Slice u ) P i dt i idx → f {
    ? == dt ST_F32 { ^ # f ( bits_to_f32 ( _st_u32 P * idx 4 ) ) } {}
    ? == dt ST_F16 { ^ ( f16_to_f ( __st_u16 P * idx 2 ) ) } {}
    ? == dt ST_BF16 { ^ ( bf16_to_f ( __st_u16 P * idx 2 ) ) } {}
    ? == dt ST_F64 { ^ ( bits_to_f64 ( __st_u64 P * idx 8 ) ) } {}
    ? == dt ST_I8 { ^ # f ( __st_i8 P idx ) } {}
    ? == dt ST_U8 { ^ # f # i ( slice_at [u] P idx ) } {}
    ? == dt ST_BOOL { ^ ? != 0 # i ( slice_at [u] P idx ) 1.0 0.0 } {}
    ? == dt ST_I16 { ^ # f ( __st_i16 P * idx 2 ) } {}
    ? == dt ST_U16 { ^ # f ( __st_u16 P * idx 2 ) } {}
    ? == dt ST_I32 { ^ # f ( __st_i32 P * idx 4 ) } {}
    ? == dt ST_U32 { ^ # f ( _st_u32 P * idx 4 ) } {}
    ? | == dt ST_I64 == dt ST_U64 { ^ # f ( __st_u64 P * idx 8 ) } {}
    ^ 0.0
}

// Elements [first, first+count) of tensor `idx`, as f32 BYTES (4 per
// element) — the same shape of result gguf_dequant returns, so a caller can
// upload it to the device without knowing which container it came from.
@ st_dequant_range St h i idx i first i count → !( Vec u ) String {
    : StImpl s ( arc_get [StImpl] . h a )
    ? | < idx 0 >= idx ( vec_len [StTensor] . s tensors ) {
        ^ ( __st_err_vec `safetensor: tensor index out of range` )
    } {}
    : ~ i dt -1
    : ~ i ne 0
    : ~ i off 0
    ?? ( vec_get [StTensor] . s tensors idx ) {
        T t → {
            = dt . t dtype
            = ne . t nelems
            = off . t offset
        }
        F → {}
    }
    ? | | | < first 0 < count 0 > first ne > count - ne first {
        ^ ( __st_err_vec `safetensor: element range outside the tensor` )
    } {}
    : i esz ( st_dtype_size dt )
    // The elements read, checked once: a loop to `count` over this window
    // and the output's needs no check per byte.
    : ( Slice u ) p ( slice_window [u] ( mapped_bytes . s file ) + off * first esz * count esz )
    // The output is SIZED ONCE and written through a view of it.
    //
    // The obvious loop — push four bytes per element — pays a capacity check per
    // byte, and a 378-million-element F16 checkpoint is 1.5 BILLION of them: it
    // cost 11.3 seconds of a whisper transcription, while reading the same 1.5 GB
    // off disk takes 0.25 s. Same arithmetic, same result, one allocation.
    // F32 is what the result holds: the bytes themselves, one copy.
    ? == dt ST_F32 { ^ @ !( Vec u ) String { T ( slice_to_vec [u] p ) } } {}
    : ( Vec u ) out ( vec_zeroed [u] * count 4 )
    : ( Slice u ) q ( slice_window [u] ( slice_from_vec [u] out ) 0 * count 4 )
    : ~ i k 0
    ? == dt ST_F16 {
        ~ < k count {
            : i bits ( f16_bits_to_f32_bits ( __st_u16 p * k 2 ) )
            ( slice_put_u32_le q * k 4 bits )
            = k + k 1
        }
    } { ? == dt ST_BF16 {
            ~ < k count {
                : i bits << ( __st_u16 p * k 2 ) 16
                ( slice_put_u32_le q * k 4 bits )
                = k + k 1
            }
        } {
            ~ < k count {
                : f v ( __st_read_f p dt k )
                ( slice_put_u32_le q * k 4 # i ( f32_to_bits # f32 v ) )
                = k + k 1
            }
        } }
    ^ @ !( Vec u ) String { T out }
}

@ st_dequant St h i idx → !( Vec u ) String {
    : StImpl s ( arc_get [StImpl] . h a )
    ? | < idx 0 >= idx ( vec_len [StTensor] . s tensors ) {
        ^ ( __st_err_vec `safetensor: tensor index out of range` )
    } {}
    : ~ i ne 0
    ?? ( vec_get [StTensor] . s tensors idx ) {
        T t → { = ne . t nelems }
        F → {}
    }
    ^ ( st_dequant_range h idx 0 ne )
}
