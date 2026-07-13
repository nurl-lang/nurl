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
// are addressed straight out of the mapping, so inspecting a multi-GB model
// costs no RAM.
//
//   ( st_open path )                → !*St String
//   ( st_n_tensors s )              → i
//   ( st_find_tensor s name )       → i        (-1 = absent)
//   ( st_tensor_ptr s t )           → *u       (into the mapping)
//   ( st_dequant s idx )            → !( Vec u ) String   — f32 bytes
//   ( st_dequant_range s idx first count ) → !( Vec u ) String
//   ( st_close s )                  → v

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`

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

: St {
    * u map
    i map_size
    b from_mmap
    ( Vec u ) buf
    ( Vec StTensor ) tensors
    i data_off  // absolute offset of the tensor-data region
    i data_size
}

@ __st_errs s msg → !*St String {
    ^ @ !*St String { F ( string_from msg ) }
}

@ __st_err_vec s msg → !( Vec u ) String {
    ^ @ !( Vec u ) String { F ( string_from msg ) }
}

@ __st_free_tensors ( Vec StTensor ) v → v {
    ( vec_free_with [StTensor] v \ StTensor t → v { ( string_free . t name ) } )
}

// ── parse ───────────────────────────────────────────────────────────

// Read the u64 header length from the first 8 bytes. Little-endian, and a
// value ≥ 2^63 surfaces as negative — which the caller rejects.
@ __st_hdr_len * u p → i {
    : ~ i v 0
    : ~ i k 7
    ~ >= k 0 {
        = v | << v 8 # i . p k
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

@ __st_parse * u p i n → !*St String {
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
    : ~ i k 0
    ~ < k hlen {
        ( string_push_char hdr # i . p + 8 k )
        = k + k 1
    }
    : !Json JsonError jr ( json_parse ( string_data hdr ) )
    ( string_free hdr )
    : ~ Json root ( json_null )
    ?? jr {
        T j → { = root j }
        F e → {
            : String m ( json_format_error e )
            : String msg ( string_from `safetensor: header is not valid JSON: ` )
            ( string_push_str msg ( string_data m ) )
            ( string_free m )
            ^ @ !*St String { F msg }
        }
    }
    ? ( json_is_obj root ) {} {
        ( json_free root )
        ^ ( __st_errs `safetensor: header JSON is not an object` )
    }

    : *St s # *St ( nurl_alloc Z St )
    = . s tensors ( vec_new [StTensor] )
    = . s data_off data_off
    = . s data_size data_size
    = . s map p
    = . s map_size n
    = . s from_mmap F
    = . s buf ( vec_new [u] )

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
                                ( string_free err )
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
                                    ( string_free err )
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
                                                ( string_free err )
                                                = err ( string_from `safetensor: shape is not an array` )
                                            }
                                            ? ok {
                                                = nd ( json_arr_len sh )
                                                ? > nd 4 {
                                                    = ok F
                                                    ( string_free err )
                                                    = err ( string_from `safetensor: more than 4 dimensions` )
                                                } {}
                                                ? ok {
                                                    ? > nd 0 { = d0 ( __st_dim sh 0 ) } {}
                                                    ? > nd 1 { = d1 ( __st_dim sh 1 ) } {}
                                                    ? > nd 2 { = d2 ( __st_dim sh 2 ) } {}
                                                    ? > nd 3 { = d3 ( __st_dim sh 3 ) } {}
                                                    ? | | | < d0 0 < d1 0 < d2 0 < d3 0 {
                                                        = ok F
                                                        ( string_free err )
                                                        = err ( string_from `safetensor: shape dimension is not a non-negative integer` )
                                                    } {}
                                                } {}
                                            } {}
                                        }
                                        F → {
                                            = ok F
                                            ( string_free err )
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
                                                ( string_free err )
                                                = err ( string_from `safetensor: data_offsets is not a 2-element array` )
                                            }
                                        }
                                        F → {
                                            = ok F
                                            ( string_free err )
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
                                        ( string_free err )
                                        = err ( string_from `safetensor: tensor '` )
                                        ( string_push_str err key )
                                        ( string_push_str err `' has data_offsets outside the file or the wrong extent for its dtype/shape` )
                                    } {
                                        ( vec_push [StTensor] . s tensors @ StTensor {
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
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
    ( json_free root )
    ? ok {} {
        ( __st_free_tensors . s tensors )
        ( vec_free [u] . s buf )
        ( nurl_free # s s )
        ^ @ !*St String { F err }
    }
    ( string_free err )
    ^ @ !*St String { T s }
}

// ── open / close ────────────────────────────────────────────────────

// mmap-backed where the platform has it (POSIX), a whole-file read where it
// does not (wasm, win32) — correct everywhere, lazy where it matters.
@ st_open s path → !*St String {
    ? != ( posix_const `MAP_PRIVATE` ) -1 {
        : i32 fd ( open path # i32 ( posix_const `O_RDONLY` ) # i32 0 )
        ? < # i fd 0 {
            : String m ( string_from `safetensor: cannot open ` )
            ( string_push_str m path )
            ^ @ !*St String { F m }
        } {}
        : i sz ( lseek fd 0 # i32 2 )
        ? < sz 8 {
            : i _c ( close # i fd )
            ^ ( __st_errs `safetensor: file too small (< 8 bytes)` )
        } {}
        : *u m ( mmap # *u 0 sz # i32 ( posix_const `PROT_READ` ) # i32 ( posix_const `MAP_PRIVATE` ) fd 0 )
        : i _c ( close # i fd )
        ? == # i m -1 { ^ ( __st_errs `safetensor: mmap failed` ) } {}
        : !*St String r ( __st_parse m sz )
        ?? r {
            T s → {
                = . s from_mmap T
                ^ @ !*St String { T s }
            }
            F e → {
                : i32 _u ( munmap m sz )
                ^ @ !*St String { F e }
            }
        }
    } {
        : !( Vec u ) IoErr r ( read_file_bytes path )
        ?? r {
            T data → {
                : !*St String pr ( __st_parse ( vec_data [u] data ) ( vec_len [u] data ) )
                ?? pr {
                    T s → {
                        // adopt the file buffer (St is manually managed — no
                        // auto-drop reaches its fields)
                        ( vec_free [u] . s buf )
                        = . s buf data
                        ^ @ !*St String { T s }
                    }
                    F e → {
                        ( vec_free [u] data )
                        ^ @ !*St String { F e }
                    }
                }
            }
            F _ → {
                : String m ( string_from `safetensor: cannot read ` )
                ( string_push_str m path )
                ^ @ !*St String { F m }
            }
        }
    }
}

// Parse an in-memory image. BORROWS `data` — the caller keeps the vec alive
// until st_close and frees it afterwards.
@ st_parse_bytes ( Vec u ) data → !*St String {
    ^ ( __st_parse ( vec_data [u] data ) ( vec_len [u] data ) )
}

@ st_close * St s → v {
    ( __st_free_tensors . s tensors )
    ? . s from_mmap {
        : i32 _u ( munmap . s map . s map_size )
    } {}
    ( vec_free [u] . s buf )
    ( nurl_free # s s )
}

// ── accessors ───────────────────────────────────────────────────────

@ st_n_tensors * St s → i { ^ ( vec_len [StTensor] . s tensors ) }

@ st_data_size * St s → i { ^ . s data_size }

@ st_find_tensor * St s s name → i {
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

// The tensor's bytes, straight out of the mapping. Borrowed: valid until
// st_close.
@ st_tensor_ptr * St s StTensor t → *u {
    ^ # *u + # i . s map . t offset
}

// ── dequantisation to f32 ───────────────────────────────────────────
// Every safetensors dtype is fixed-width, so an element range is exact — no
// block alignment to respect (which is what makes this simpler than gguf).

// Little-endian scalar reads straight out of the mapping. stdlib's
// bytes_read_* take a Vec; a mapping is a raw pointer, so these are the
// pointer-shaped siblings (the same idiom gguf/dequant.nu uses).
@ __st_u16 * u P i o → i {
    ^ | # i . P o << # i . P + o 1 8
}

@ __st_u32 * u P i o → i {
    ^ | # i . P o | << # i . P + o 1 8 | << # i . P + o 2 16 << # i . P + o 3 24
}

@ __st_u64 * u P i o → i {
    : i lo ( __st_u32 P o )
    : i hi ( __st_u32 P + o 4 )
    ^ | lo << hi 32
}

// Sign-extending readers: the raw word is unsigned, the dtype is not.
@ __st_i8 * u P i o → i {
    : i v # i . P o
    ^ ? > v 127 - v 256 v
}

@ __st_i16 * u P i o → i {
    : i v ( __st_u16 P o )
    ^ ? > v 32767 - v 65536 v
}

@ __st_i32 * u P i o → i {
    : i v ( __st_u32 P o )
    ^ ? > v 2147483647 - v 4294967296 v
}

// One element of a tensor, as f32. Every dtype widens to f32 here — an f64
// loses precision (by construction: the device runs f32) and an integer
// tensor becomes its numeric value.
@ __st_read_f * u P i dt i idx → f {
    ? == dt ST_F32 { ^ # f ( bits_to_f32 ( __st_u32 P * idx 4 ) ) } {}
    ? == dt ST_F16 { ^ ( f16_to_f ( __st_u16 P * idx 2 ) ) } {}
    ? == dt ST_BF16 { ^ ( bf16_to_f ( __st_u16 P * idx 2 ) ) } {}
    ? == dt ST_F64 { ^ ( bits_to_f64 ( __st_u64 P * idx 8 ) ) } {}
    ? == dt ST_I8 { ^ # f ( __st_i8 P idx ) } {}
    ? == dt ST_U8 { ^ # f # i . P idx } {}
    ? == dt ST_BOOL { ^ ? != 0 # i . P idx 1.0 0.0 } {}
    ? == dt ST_I16 { ^ # f ( __st_i16 P * idx 2 ) } {}
    ? == dt ST_U16 { ^ # f ( __st_u16 P * idx 2 ) } {}
    ? == dt ST_I32 { ^ # f ( __st_i32 P * idx 4 ) } {}
    ? == dt ST_U32 { ^ # f ( __st_u32 P * idx 4 ) } {}
    ? | == dt ST_I64 == dt ST_U64 { ^ # f ( __st_u64 P * idx 8 ) } {}
    ^ 0.0
}

// Elements [first, first+count) of tensor `idx`, as f32 BYTES (4 per
// element) — the same shape of result gguf_dequant returns, so a caller can
// upload it to the device without knowing which container it came from.
@ st_dequant_range * St s i idx i first i count → !( Vec u ) String {
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
    : *u p # *u + # i . s map off
    // The output is SIZED ONCE and written through a raw pointer.
    //
    // The obvious loop — push four bytes per element — pays a capacity check per
    // byte, and a 378-million-element F16 checkpoint is 1.5 BILLION of them: it
    // cost 11.3 seconds of a whisper transcription, while reading the same 1.5 GB
    // off disk takes 0.25 s. Same arithmetic, same result, one allocation.
    : ( Vec u ) out ( vec_with_cap [u] * count 4 )
    : b _sz ( vec_set_len [u] out * count 4 )
    : *u q ( vec_data [u] out )
    : ~ i k 0
    ~ < k count {
        : f v ( __st_read_f p dt + first k )
        : i bits # i ( f32_to_bits # f32 v )
        : i o * k 4
        = . q o # u & bits 255
        = . q + o 1 # u & >> bits 8 255
        = . q + o 2 # u & >> bits 16 255
        = . q + o 3 # u & >> bits 24 255
        = k + k 1
    }
    ^ @ !( Vec u ) String { T out }
}

@ st_dequant * St s i idx → !( Vec u ) String {
    ? | < idx 0 >= idx ( vec_len [StTensor] . s tensors ) {
        ^ ( __st_err_vec `safetensor: tensor index out of range` )
    } {}
    : ~ i ne 0
    ?? ( vec_get [StTensor] . s tensors idx ) {
        T t → { = ne . t nelems }
        F → {}
    }
    ^ ( st_dequant_range s idx 0 ne )
}
