// packages/torchpt/src/torchpt.nu — read PyTorch `.pt` / `.pth`
// checkpoints in pure NURL.
//
// A modern `torch.save` file is a ZIP archive:
//
//     <name>/data.pkl        the object graph, pickled
//     <name>/data/<key>      one flat storage per key, raw little-endian
//     <name>/version         etc.
//
// Tensors in the pickle are `_rebuild_tensor_v2(storage, offset, size,
// stride, …)` calls whose storage is a *persistent id* naming one of the
// `data/<key>` members. So reading a checkpoint is: parse the zip, parse
// the pickle as DATA (never executing it — see src/pickle.nu), then map
// each tensor onto a byte range of the mapping.
//
// mmap-backed and lazy, like safetensor and gguf: only the pickle is
// read up front, so listing the tensors of a 4.6 GB checkpoint costs
// megabytes, not gigabytes. Tensor bytes are addressed straight out of
// the mapping.
//
// Entries are ZIP-stored (torch never deflates tensor data), which is
// what makes in-place addressing possible; a deflated storage is
// reported rather than silently mis-read.
//
//   ( pt_open path )              → !*Pt String
//   ( pt_close p )                → v
//   ( pt_n_tensors p )            → i
//   ( pt_name p idx )             → s      BORROWED
//   ( pt_find p name )            → i      -1 when absent
//   ( pt_dtype p idx )            → i      PKS_*
//   ( pt_ndim p idx )             → i
//   ( pt_dim p idx j )            → i
//   ( pt_nelems p idx )           → i
//   ( pt_nbytes p idx )           → i
//   ( pt_is_contiguous p idx )    → b
//   ( pt_tensor_ptr p idx )       → *u     into the mapping
//   ( pt_dequant p idx )          → !( Vec u ) String    f32 LE bytes
//   ( pt_dequant_range p idx first count ) → !( Vec u ) String
//   ( pt_read_f64 p idx first count dst )  → b            into an f64 buffer
//
// Names are the dotted path from the pickle root: a plain state_dict
// gives `blocks.0.attn.qkv.weight`, while a training checkpoint saved as
// `{"model": sd, "epoch": n}` gives `model.blocks.0.…`. Nothing is
// stripped — what the file says is what you get.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/zip.nu`
$ `packages/torchpt/src/pickle.nu`

// Up to 8 dimensions is more than any real checkpoint tensor uses; the
// limit keeps the per-tensor record a fixed size.
: i PT_MAX_DIMS 8

: PtTensor {
    String name
    i dtype  // PKS_* storage class
    i ndim
    i nelems
    i data_off  // absolute FILE offset of element 0
    i nbytes  // logical size: nelems x element size
    i contiguous  // 1 = row-major, 0 = a view we can only describe
    s shape  // 16 slots: dims 0..7, then strides 8..15
}

: Pt {
    * u map
    i map_size
    b from_mmap
    ( Vec u ) buf
    ( Vec PtTensor ) tensors
}

@ __pt_errs s msg → !*Pt String {
    ^ @ !*Pt String { F ( string_from msg ) }
}

@ __pt_err_vec s msg → !( Vec u ) String {
    ^ @ !( Vec u ) String { F ( string_from msg ) }
}

@ __pt_free_tensors ( Vec PtTensor ) v → v {
    ( vec_free_with [PtTensor] v \ PtTensor t → v {
        ( string_free . t name )
        ( nurl_free . t shape )
    } )
}

// ── accessors ───────────────────────────────────────────────────────

@ pt_n_tensors * Pt p → i { ^ ( vec_len [PtTensor] . p tensors ) }

@ __pt_at * Pt p i idx → ?PtTensor { ^ ( vec_get [PtTensor] . p tensors idx ) }

@ pt_name * Pt p i idx → s {
    ?? ( __pt_at p idx ) { T t → ^ ( string_data . t name ) F → ^ `` }
}

@ pt_dtype * Pt p i idx → i {
    ?? ( __pt_at p idx ) { T t → ^ . t dtype F → ^ PKS_UNKNOWN }
}

@ pt_ndim * Pt p i idx → i {
    ?? ( __pt_at p idx ) { T t → ^ . t ndim F → ^ 0 }
}

@ pt_dim * Pt p i idx i j → i {
    ?? ( __pt_at p idx ) {
        T t → {
            ? | < j 0 >= j . t ndim { ^ 0 } {}
            ^ ( nurl_peek . t shape j )
        }
        F → ^ 0
    }
}

@ pt_stride * Pt p i idx i j → i {
    ?? ( __pt_at p idx ) {
        T t → {
            ? | < j 0 >= j . t ndim { ^ 0 } {}
            ^ ( nurl_peek . t shape + 8 j )
        }
        F → ^ 0
    }
}

@ pt_nelems * Pt p i idx → i {
    ?? ( __pt_at p idx ) { T t → ^ . t nelems F → ^ 0 }
}

@ pt_nbytes * Pt p i idx → i {
    ?? ( __pt_at p idx ) { T t → ^ . t nbytes F → ^ 0 }
}

@ pt_is_contiguous * Pt p i idx → b {
    ?? ( __pt_at p idx ) { T t → ^ == . t contiguous 1 F → ^ F }
}

@ pt_offset * Pt p i idx → i {
    ?? ( __pt_at p idx ) { T t → ^ . t data_off F → ^ -1 }
}

// Raw bytes of a tensor, addressed in the mapping. Valid until pt_close.
@ pt_tensor_ptr * Pt p i idx → *u {
    ?? ( __pt_at p idx ) {
        T t → ^ # *u + # i . p map . t data_off
        F → ^ # *u 0
    }
}

@ pt_find * Pt p s name → i {
    : i n ( pt_n_tensors p )
    : ~ i j 0
    ~ < j n {
        ? ( nurl_str_eq ( pt_name p j ) name ) { ^ j } {}
        = j + j 1
    }
    ^ -1
}

// Shape rendered as "2x3x4" — for CLI listings and error messages.
@ pt_shape_str * Pt p i idx → String {
    : String s ( string_new )
    : i nd ( pt_ndim p idx )
    ? == nd 0 { ( string_push_str s `scalar` ) ^ s } {}
    : ~ i j 0
    ~ < j nd {
        ? > j 0 { ( string_push_char s 120 ) } {}
        ( string_push_int s ( pt_dim p idx j ) )
        = j + j 1
    }
    ^ s
}

// ── building the tensor table ───────────────────────────────────────

// Row-major? stride[nd-1] must be 1 and each earlier stride the product
// of the dims to its right. Size-1 axes carry an arbitrary stride in
// torch, so they are skipped rather than treated as a mismatch.
@ __pt_contiguous * Pk k i node i nd → b {
    ? == nd 0 { ^ T } {}
    : ~ i want 1
    : ~ i j - nd 1
    ~ >= j 0 {
        : i d ( pk_tensor_dim k node j )
        ? != d 1 {
            ? != ( pk_tensor_stride k node j ) want { ^ F } {}
        } {}
        = want * want d
        = j - j 1
    }
    ^ T
}

// One PK_TENSOR → one PtTensor, with every extent checked against the
// zip member the storage actually resolves to.
@ __pt_add_tensor ZipArchive za s prefix * Pk k i node String name
( Vec PtTensor ) out ( Vec String ) errs → v {
    ? > 0 ( vec_len [String] errs ) { ^ v } {}
    : i nd ( pk_tensor_ndim k node )
    ? > nd PT_MAX_DIMS {
        ( vec_push [String] errs ( string_from `torchpt: tensor has more than 8 dimensions` ) )
        ^ v
    } {}
    : i sid ( pk_tensor_storage k node )
    : i dtype ( pk_storage_dtype k sid )
    : i esize ( pk_storage_esize dtype )
    ? == esize 0 {
        : String m ( string_from `torchpt: unsupported storage class for ` )
        ( string_push_str m ( string_data name ) )
        ( vec_push [String] errs m )
        ^ v
    } {}
    // storage key → the `<prefix>data/<key>` member
    : String member ( string_from prefix )
    ( string_push_str member `data/` )
    ( string_push_str member ( pk_storage_key k sid ) )
    : i ent ( zip_find za ( string_data member ) )
    ? < ent 0 {
        : String m ( string_from `torchpt: missing storage member ` )
        ( string_push_str m ( string_data member ) )
        ( vec_push [String] errs m )
        ( string_free member )
        ^ v
    } {}
    : i method ?? ( zip_method_at za ent ) { T x → x F → -1 }
    ? != method 0 {
        : String m ( string_from `torchpt: storage is compressed, not stored: ` )
        ( string_push_str m ( string_data member ) )
        ( vec_push [String] errs m )
        ( string_free member )
        ^ v
    } {}
    : i store_bytes ?? ( zip_size_at za ent ) { T x → x F → 0 }
    : i base ( zip_data_off za ent )
    ? < base 0 {
        : String m ( string_from `torchpt: unreadable local header for ` )
        ( string_push_str m ( string_data member ) )
        ( vec_push [String] errs m )
        ( string_free member )
        ^ v
    } {}
    ( string_free member )

    // element count, accumulated with an overflow guard rather than
    // multiplied and hoped for
    : ~ i nelems 1
    : ~ i j 0
    : ~ b bad F
    ~ < j nd {
        : i d ( pk_tensor_dim k node j )
        ? < d 0 { = bad T } {}
        ? & != d 0 > nelems / 9223372036854775807 d { = bad T } {}
        = nelems * nelems d
        = j + j 1
    }
    ? bad {
        ( vec_push [String] errs ( string_from `torchpt: tensor element count overflows` ) )
        ^ v
    } {}

    : i elem_off ( pk_tensor_offset k node )
    ? < elem_off 0 {
        ( vec_push [String] errs ( string_from `torchpt: negative storage offset` ) )
        ^ v
    } {}
    : b contig ( __pt_contiguous k node nd )
    // Reach, not extent: a view's last element is at
    // offset + Σ (dim_i − 1)·stride_i, which for a transpose is nothing
    // like nelems·esize. Bound THAT against the storage, so a strided
    // read can never leave the member it belongs to.
    : ~ i reach elem_off
    = j 0
    ~ < j nd {
        : i st ( pk_tensor_stride k node j )
        ? < st 0 { = bad T } {}
        = reach + reach * - ( pk_tensor_dim k node j ) 1 st
        = j + j 1
    }
    ? bad {
        ( vec_push [String] errs ( string_from `torchpt: negative stride` ) )
        ^ v
    } {}
    // An empty tensor reaches nothing at all — it must still start inside
    // the storage, but there is no last element to bound.
    : i need ? == nelems 0 * elem_off esize * + reach 1 esize
    ? | < need 0 > need store_bytes {
        ( vec_push [String] errs ( string_from `torchpt: tensor runs past its storage` ) )
        ^ v
    } {}

    : s shape ( nurl_zalloc 128 )
    = j 0
    ~ < j nd {
        ( nurl_poke shape j ( pk_tensor_dim k node j ) )
        ( nurl_poke shape + 8 j ( pk_tensor_stride k node j ) )
        = j + j 1
    }
    ( vec_push [PtTensor] out @ PtTensor {
        name dtype nd nelems + base * elem_off esize * nelems esize ? contig 1 0 shape } )
}

// Depth-first walk of the value tree, naming tensors by their dotted
// path. Depth is bounded: a cyclic memo graph (which a crafted pickle
// can build) would otherwise recurse forever.
@ __pt_walk ZipArchive za s prefix * Pk k i node String path
( Vec PtTensor ) out ( Vec String ) errs i depth → v {
    ? > 0 ( vec_len [String] errs ) { ^ v } {}
    ? > depth 64 { ^ v } {}
    : i kd ( pk_kind k node )
    ? == kd PK_TENSOR {
        ( __pt_add_tensor za prefix k node ( string_from ( string_data path ) ) out errs )
        ^ v
    } {}
    ? == kd PK_DICT {
        : i n ( pk_len k node )
        : ~ i j 0
        ~ < j n {
            : i keyn ( pk_key k node j )
            ? == ( pk_kind k keyn ) PK_STR {
                : String sub ( string_from ( string_data path ) )
                ? > ( nurl_str_len ( string_data path ) ) 0 { ( string_push_char sub 46 ) } {}
                ( string_push_str sub ( pk_str k keyn ) )
                ( __pt_walk za prefix k ( pk_val k node j ) sub out errs + depth 1 )
                ( string_free sub )
            } {}
            = j + j 1
        }
        ^ v
    } {}
    ? | == kd PK_LIST == kd PK_TUPLE {
        : i n ( pk_len k node )
        : ~ i j 0
        ~ < j n {
            : String sub ( string_from ( string_data path ) )
            ? > ( nurl_str_len ( string_data path ) ) 0 { ( string_push_char sub 46 ) } {}
            ( string_push_int sub j )
            ( __pt_walk za prefix k ( pk_item k node j ) sub out errs + depth 1 )
            ( string_free sub )
            = j + j 1
        }
        ^ v
    } {}
}

// ── open ────────────────────────────────────────────────────────────

@ __pt_parse * u m i sz → !*Pt String {
    : !ZipArchive ZipErr zr ( zip_open_ptr m sz )
    ?? zr {
        F e → {
            : String msg ( string_from `torchpt: not a zip-format checkpoint (` )
            ( string_push_str msg ( zip_err_name # ZipErr e ) )
            ( string_push_char msg 41 )
            ^ @ !*Pt String { F msg }
        }
        T za → {
            // Locate `<prefix>data.pkl`; the prefix is the archive's
            // internal directory name, which torch derives from the
            // output filename and which we must reuse verbatim to find
            // the storages.
            : i count ( zip_count za )
            : ~ i pkl -1
            : ~ i j 0
            ~ & < j count < pkl 0 {
                ?? ( zip_name_at za j ) {
                    T nm → {
                        : s nd ( string_data nm )
                        : i ln ( nurl_str_len nd )
                        ? >= ln 8 {
                            ? ( nurl_str_eq ( nurl_str_slice nd - ln 8 8 ) `data.pkl` ) { = pkl j } {}
                        } {}
                        ( string_free nm )
                    }
                    F → {}
                }
                = j + j 1
            }
            ? < pkl 0 {
                ( zip_close za )
                ^ ( __pt_errs `torchpt: archive has no data.pkl — not a torch.save file` )
            } {}
            : String pklname ?? ( zip_name_at za pkl ) { T nm → nm F → ( string_new ) }
            : i pl ( nurl_str_len ( string_data pklname ) )
            : String prefix ( string_from ( nurl_str_slice ( string_data pklname ) 0 - pl 8 ) )
            ( string_free pklname )

            : !( Vec u ) ZipErr px ( zip_extract za pkl )
            ?? px {
                F e → {
                    ( string_free prefix )
                    ( zip_close za )
                    : String msg ( string_from `torchpt: cannot read data.pkl (` )
                    ( string_push_str msg ( zip_err_name # ZipErr e ) )
                    ( string_push_char msg 41 )
                    ^ @ !*Pt String { F msg }
                }
                T pdata → {
                    : !*Pk String kr ( pk_parse ( vec_data [u] pdata ) ( vec_len [u] pdata ) )
                    ?? kr {
                        F e → {
                            ( vec_free [u] pdata )
                            ( string_free prefix )
                            ( zip_close za )
                            ^ @ !*Pt String { F e }
                        }
                        T k → {
                            : ( Vec PtTensor ) tensors ( vec_new [PtTensor] )
                            : ( Vec String ) errs ( vec_new [String] )
                            : String root ( string_new )
                            ( __pt_walk za ( string_data prefix ) k ( pk_root k ) root tensors errs 0 )
                            ( string_free root )
                            ( pk_free k )
                            ( vec_free [u] pdata )
                            ( string_free prefix )
                            ( zip_close za )
                            ? > ( vec_len [String] errs ) 0 {
                                : String em ?? ( vec_get [String] errs 0 )
                                { T s → ( string_from ( string_data s ) ) F → ( string_from `torchpt: parse failed` ) }
                                ( __pt_free_tensors tensors )
                                ( vec_free_with [String] errs \ String s → v { ( string_free s ) } )
                                ^ @ !*Pt String { F em }
                            } {}
                            ( vec_free_with [String] errs \ String s → v { ( string_free s ) } )
                            : *Pt p # *Pt ( nurl_alloc Z Pt )
                            = . p map m
                            = . p map_size sz
                            = . p from_mmap F
                            = . p buf ( vec_new [u] )
                            = . p tensors tensors
                            ^ @ !*Pt String { T p }
                        }
                    }
                }
            }
        }
    }
}

@ pt_open s path → !*Pt String {
    ? != ( posix_const `MAP_PRIVATE` ) -1 {
        : i32 fd ( open path # i32 ( posix_const `O_RDONLY` ) # i32 0 )
        ? < # i fd 0 {
            : String m ( string_from `torchpt: cannot open ` )
            ( string_push_str m path )
            ^ @ !*Pt String { F m }
        } {}
        : i sz ( lseek fd 0 # i32 2 )
        ? < sz 22 {
            : i _c ( close # i fd )
            ^ ( __pt_errs `torchpt: file too small to be a zip archive` )
        } {}
        : *u m ( mmap # *u 0 sz # i32 ( posix_const `PROT_READ` ) # i32 ( posix_const `MAP_PRIVATE` ) fd 0 )
        : i _c ( close # i fd )
        ? == # i m -1 { ^ ( __pt_errs `torchpt: mmap failed` ) } {}
        : !*Pt String r ( __pt_parse m sz )
        ?? r {
            T p → { = . p from_mmap T ^ @ !*Pt String { T p } }
            F e → {
                : i32 _u ( munmap m sz )
                ^ @ !*Pt String { F e }
            }
        }
    } {
        : !( Vec u ) IoErr r ( read_file_bytes path )
        ?? r {
            T data → {
                : !*Pt String pr ( __pt_parse ( vec_data [u] data ) ( vec_len [u] data ) )
                ?? pr {
                    T p → {
                        ( vec_free [u] . p buf )
                        = . p buf data
                        ^ @ !*Pt String { T p }
                    }
                    F e → { ( vec_free [u] data ) ^ @ !*Pt String { F e } }
                }
            }
            F _ → {
                : String m ( string_from `torchpt: cannot read ` )
                ( string_push_str m path )
                ^ @ !*Pt String { F m }
            }
        }
    }
}

@ pt_close * Pt p → v {
    ( __pt_free_tensors . p tensors )
    ? . p from_mmap { : i32 _u ( munmap . p map . p map_size ) } {}
    ( vec_free [u] . p buf )
    ( nurl_free # s p )
}

// ── widening to f32 ─────────────────────────────────────────────────
//
// Same contract as safetensor's st_dequant: every dtype widens to f32
// little-endian bytes, so downstream code has one representation to
// handle. Views read correctly too — the element at logical index n is
// found through the strides, so a transposed or sliced tensor comes out
// in ITS order, not the storage's.

// Storage-element offset of a tensor's logical element `n`, walking the
// shape from the fastest-varying axis outward. Contiguous tensors take
// the identity path, so the common case costs one comparison.
@ __pt_elem_index * Pt p i idx i n → i {
    ?? ( __pt_at p idx ) {
        F → ^ 0
        T t → {
            ? == . t contiguous 1 { ^ n } {}
            : ~ i rem n
            : ~ i off 0
            : ~ i j - . t ndim 1
            ~ >= j 0 {
                : i d ( nurl_peek . t shape j )
                ? > d 0 {
                    = off + off * % rem d ( nurl_peek . t shape + 8 j )
                    = rem / rem d
                } {}
                = j - j 1
            }
            ^ off
        }
    }
}

@ __pt_u16 * u P i o → i { ^ + # i . P o * # i . P + o 1 256 }

@ __pt_u32 * u P i o → i { ^ + ( __pt_u16 P o ) * ( __pt_u16 P + o 2 ) 65536 }

@ __pt_u64 * u P i o → i { ^ + ( __pt_u32 P o ) * ( __pt_u32 P + o 4 ) 4294967296 }

@ __pt_elem_f32bits i dtype * u P i off → i {
    ? == dtype PKS_F32 { ^ ( __pt_u32 P off ) } {}
    ? == dtype PKS_F64 { ^ ( f32_to_bits # f32 ( bits_to_f64 ( __pt_u64 P off ) ) ) } {}
    ? == dtype PKS_F16 { ^ ( f16_bits_to_f32_bits ( __pt_u16 P off ) ) } {}
    ? == dtype PKS_BF16 { ^ ( bf16_bits_to_f32_bits ( __pt_u16 P off ) ) } {}
    ? == dtype PKS_I64 {
        : i raw ( __pt_u64 P off )
        ^ ( f32_to_bits # f32 # f raw )
    } {}
    ? == dtype PKS_I32 {
        : i raw ( __pt_u32 P off )
        ^ ( f32_to_bits # f32 # f ? >= raw 2147483648 - raw 4294967296 raw )
    } {}
    ? == dtype PKS_I16 {
        : i raw ( __pt_u16 P off )
        ^ ( f32_to_bits # f32 # f ? >= raw 32768 - raw 65536 raw )
    } {}
    ? == dtype PKS_I8 {
        : i raw # i . P off
        ^ ( f32_to_bits # f32 # f ? >= raw 128 - raw 256 raw )
    } {}
    ? | == dtype PKS_U8 == dtype PKS_BOOL { ^ ( f32_to_bits # f32 # f # i . P off ) } {}
    ^ 0
}

@ pt_dequant_range * Pt p i idx i first i count → !( Vec u ) String {
    ? | < idx 0 >= idx ( pt_n_tensors p ) { ^ ( __pt_err_vec `torchpt: tensor index out of range` ) } {}
    : i nelems ( pt_nelems p idx )
    ? | | < first 0 < count 0 > + first count nelems {
        ^ ( __pt_err_vec `torchpt: element range outside the tensor` )
    } {}
    : i dtype ( pt_dtype p idx )
    : i esize ( pk_storage_esize dtype )
    ? == esize 0 { ^ ( __pt_err_vec `torchpt: unsupported dtype` ) } {}
    : *u base ( pt_tensor_ptr p idx )
    : ( Vec u ) out ( vec_with_cap [u] ? > * count 4 0 * count 4 1 )
    : ~ i j 0
    ~ < j count {
        : i bits ( __pt_elem_f32bits dtype base * ( __pt_elem_index p idx + first j ) esize )
        ( vec_push [u] out # u & bits 255 )
        ( vec_push [u] out # u & / bits 256 255 )
        ( vec_push [u] out # u & / bits 65536 255 )
        ( vec_push [u] out # u & / bits 16777216 255 )
        = j + j 1
    }
    ^ @ !( Vec u ) String { T out }
}

@ pt_dequant * Pt p i idx → !( Vec u ) String {
    ^ ( pt_dequant_range p idx 0 ( pt_nelems p idx ) )
}

// Read `count` elements starting at `first` straight into a caller's f64
// buffer — the shape the tensor package wants, without a byte round-trip.
@ pt_read_f64 * Pt p i idx i first i count * f dst → b {
    ? | < idx 0 >= idx ( pt_n_tensors p ) { ^ F } {}
    : i nelems ( pt_nelems p idx )
    ? | | < first 0 < count 0 > + first count nelems { ^ F } {}
    : i dtype ( pt_dtype p idx )
    : i esize ( pk_storage_esize dtype )
    ? == esize 0 { ^ F } {}
    : *u base ( pt_tensor_ptr p idx )
    : ~ i j 0
    ~ < j count {
        : i off * ( __pt_elem_index p idx + first j ) esize
        // f64 storages keep their full precision; everything else is
        // exactly representable in f32 first.
        : f x ? == dtype PKS_F64 ( bits_to_f64 ( __pt_u64 base off ) )
        # f ( bits_to_f32 ( __pt_elem_f32bits dtype base off ) )
        = . dst j x
        = j + j 1
    }
    ^ T
}
