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
// megabytes, not gigabytes. Tensor bytes are read straight out of the
// mapping (stdlib/std/mmap.nu), through checked views of it.
//
// Entries are ZIP-stored (torch never deflates tensor data), which is
// what makes in-place addressing possible; a deflated storage is
// reported rather than silently mis-read.
//
//   ( pt_open path )              → !Pt String
//   ( pt_close p )                → v      early release (optional)
//   an empty slot is a ?Pt
//   ( pt_n_tensors p )            → i
//   ( pt_name p idx )             → s      BORROWED
//   ( pt_find p name )            → i      -1 when absent
//   ( pt_dtype p idx )            → i      PKS_*
//   ( pt_ndim p idx )             → i
//   ( pt_dim p idx j )            → i
//   ( pt_nelems p idx )           → i
//   ( pt_nbytes p idx )           → i
//   ( pt_is_contiguous p idx )    → b
//   ( pt_tensor_bytes p idx )     → ( Slice u )   its nbytes, out of the
//                                    mapping — a view held to `p`
//   ( pt_tensor_ptr p idx )       → *u     raw: their address
//   ( pt_dequant p idx )          → !( Vec u ) String    f32 LE bytes
//   ( pt_dequant_range p idx first count ) → !( Vec u ) String
//   ( pt_read_f64_into p idx first count dst ) → b        into a ( Slice f )
//   ( pt_read_f64 p idx first count dst )  → b            raw: into a *f
//
// Names are the dotted path from the pickle root: a plain state_dict
// gives `blocks.0.attn.qkv.weight`, while a training checkpoint saved as
// `{"model": sd, "epoch": n}` gives `model.blocks.0.…`. Nothing is
// stripped — what the file says is what you get.
//
// A Pt is a handle: every copy is the same open checkpoint, and the last
// owner unmaps it. Nothing here is released by hand.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/zip.nu`
$ `pickle.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/mmap.nu`
$ `stdlib/core/slice.nu`

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
    i shape_at  // where its 16 slots start in the Pt's `dims`: dims 0..7, then strides 8..15
}

: PtImpl {
    MappedFile file  // the checkpoint's bytes: a mapping, or the file read whole
    ( Vec PtTensor ) tensors
    ( Vec i ) dims  // 16 slots per tensor (PtTensor.shape_at): one array, not one per tensor
}

// A Pt is a handle on its state in an Arc (stdlib/std/arc.nu), frozen once
// parsed: every copy is the same open checkpoint, and the last owner lets
// go of the mapping.
: Pt { ( Arc PtImpl ) a }

@ Pt_share Pt h → Pt { ^ @ Pt { ( arc_clone [PtImpl] . h a ) } }

@ Pt_drop sink Pt h → v {}

@ _pt_geti ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F → ^ 0 } }

@ __pt_errs s msg → !Pt String {
    ^ @ !Pt String { F ( string_from msg ) }
}

@ __pt_err_vec s msg → !( Vec u ) String {
    ^ @ !( Vec u ) String { F ( string_from msg ) }
}

// ── accessors ───────────────────────────────────────────────────────

@ pt_n_tensors Pt p__h → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ^ ( vec_len [PtTensor] . p tensors )
}

@ __pt_at PtImpl p i idx → ?PtTensor { ^ ( vec_get [PtTensor] . p tensors idx ) }

@ pt_name Pt p__h i idx → s {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ ( string_data . t name ) F → ^ `` }
}

@ pt_dtype Pt p__h i idx → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ . t dtype F → ^ PKS_UNKNOWN }
}

@ pt_ndim Pt p__h i idx → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ . t ndim F → ^ 0 }
}

@ pt_dim Pt p__h i idx i j → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) {
        T t → {
            ? | < j 0 >= j . t ndim { ^ 0 } {}
            ^ ( _pt_geti . p dims + . t shape_at j )
        }
        F → ^ 0
    }
}

@ pt_stride Pt p__h i idx i j → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) {
        T t → {
            ? | < j 0 >= j . t ndim { ^ 0 } {}
            ^ ( _pt_geti . p dims + + . t shape_at 8 j )
        }
        F → ^ 0
    }
}

@ pt_nelems Pt p__h i idx → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ . t nelems F → ^ 0 }
}

@ pt_nbytes Pt p__h i idx → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ . t nbytes F → ^ 0 }
}

@ pt_is_contiguous Pt p__h i idx → b {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ == . t contiguous 1 F → ^ F }
}

@ pt_offset Pt p__h i idx → i {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) { T t → ^ . t data_off F → ^ -1 }
}

// A tensor's bytes — its `nbytes` from element 0 — straight out of the
// mapping: a checked view that lives no longer than `p__h`. Empty for an
// index out of range.
@ pt_tensor_bytes Pt p__h i idx → ( Slice u ) {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ?? ( __pt_at p idx ) {
        T t → ^ ( slice_window [u] ( mapped_bytes . p file ) . t data_off . t nbytes )
        F → ^ ( slice_empty [u] )
    }
}

// Their address, for a device upload. raw: the caller keeps `p__h` alive
// while it is used; null for an index out of range.
raw @ pt_tensor_ptr Pt p__h i idx → *u {
    ? | < idx 0 >= idx ( pt_n_tensors p__h ) { ^ # *u 0 } {}
    ^ ( slice_data [u] ( pt_tensor_bytes p__h idx ) )
}

@ pt_find Pt p__h s name → i {
    : i n ( pt_n_tensors p__h )
    : ~ i j 0
    ~ < j n {
        ? ( nurl_str_eq ( pt_name p__h j ) name ) { ^ j } {}
        = j + j 1
    }
    ^ -1
}

// Shape rendered as "2x3x4" — for CLI listings and error messages.
@ pt_shape_str Pt p__h i idx → String {
    : String s ( string_new )
    : i nd ( pt_ndim p__h idx )
    ? == nd 0 { ( string_push_str s `scalar` ) ^ s } {}
    : ~ i j 0
    ~ < j nd {
        ? > j 0 { ( string_push_char s 120 ) } {}
        ( string_push_int s ( pt_dim p__h idx j ) )
        = j + j 1
    }
    ^ s
}

// ── building the tensor table ───────────────────────────────────────

// Row-major? stride[nd-1] must be 1 and each earlier stride the product
// of the dims to its right. Size-1 axes carry an arbitrary stride in
// torch, so they are skipped rather than treated as a mismatch.
@ __pt_contiguous Pk k i node i nd → b {
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
@ __pt_add_tensor ZipArchive za s prefix Pk k i node String name
( Vec PtTensor ) out ( Vec i ) dims ( Vec String ) errs → v {
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
        ^ v
    } {}
    : i method ?? ( zip_method_at za ent ) { T x → x F → -1 }
    ? != method 0 {
        : String m ( string_from `torchpt: storage is compressed, not stored: ` )
        ( string_push_str m ( string_data member ) )
        ( vec_push [String] errs m )
        ^ v
    } {}
    : i store_bytes ?? ( zip_size_at za ent ) { T x → x F → 0 }
    : i base ( zip_data_off za ent )
    ? < base 0 {
        : String m ( string_from `torchpt: unreadable local header for ` )
        ( string_push_str m ( string_data member ) )
        ( vec_push [String] errs m )
        ^ v
    } {}

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

    : i at ( vec_len [i] dims )
    = j 0
    ~ < j 8 {
        ( vec_push [i] dims ? < j nd ( pk_tensor_dim k node j ) 0 )
        = j + j 1
    }
    = j 0
    ~ < j 8 {
        ( vec_push [i] dims ? < j nd ( pk_tensor_stride k node j ) 0 )
        = j + j 1
    }
    ( vec_push [PtTensor] out @ PtTensor {
        name dtype nd nelems + base * elem_off esize * nelems esize ? contig 1 0 at } )
}

// Depth-first walk of the value tree, naming tensors by their dotted
// path. Depth is bounded: a cyclic memo graph (which a crafted pickle
// can build) would otherwise recurse forever.
@ __pt_walk ZipArchive za s prefix Pk k i node String path
( Vec PtTensor ) out ( Vec i ) dims ( Vec String ) errs i depth → v {
    ? > 0 ( vec_len [String] errs ) { ^ v } {}
    ? > depth 64 { ^ v } {}
    : i kd ( pk_kind k node )
    ? == kd PK_TENSOR {
        ( __pt_add_tensor za prefix k node ( string_from ( string_data path ) ) out dims errs )
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
                ( __pt_walk za prefix k ( pk_val k node j ) sub out dims errs + depth 1 )
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
            ( __pt_walk za prefix k ( pk_item k node j ) sub out dims errs + depth 1 )
            = j + j 1
        }
        ^ v
    } {}
}

// ── open ────────────────────────────────────────────────────────────

// Parse the checkpoint `file` holds; the Pt keeps it for as long as the
// tensors are read.
@ __pt_parse sink MappedFile file → !Pt String {
    : !ZipArchive ZipErr zr ( zip_open_mapped file )
    ?? zr {
        F e → {
            : String msg ( string_from `torchpt: not a zip-format checkpoint (` )
            ( string_push_str msg ( zip_err_name # ZipErr e ) )
            ( string_push_char msg 41 )
            ^ @ !Pt String { F msg }
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

            : !( Vec u ) ZipErr px ( zip_extract za pkl )
            ?? px {
                F e → {
                    ( zip_close za )
                    : String msg ( string_from `torchpt: cannot read data.pkl (` )
                    ( string_push_str msg ( zip_err_name # ZipErr e ) )
                    ( string_push_char msg 41 )
                    ^ @ !Pt String { F msg }
                }
                T pdata → {
                    : !Pk String kr ( pk_parse ( slice_from_vec [u] pdata ) )
                    ?? kr {
                        F e → {
                            ( zip_close za )
                            ^ @ !Pt String { F e }
                        }
                        T k → {
                            : ( Vec PtTensor ) tensors ( vec_new [PtTensor] )
                            : ( Vec i ) dims ( vec_new [i] )
                            : ( Vec String ) errs ( vec_new [String] )
                            : String root ( string_new )
                            ( __pt_walk za ( string_data prefix ) k ( pk_root k ) root tensors dims errs 0 )
                            ( zip_close za )
                            ? > ( vec_len [String] errs ) 0 {
                                : String em ?? ( vec_get [String] errs 0 )
                                { T s → ( string_from ( string_data s ) ) F → ( string_from `torchpt: parse failed` ) }
                                ^ @ !Pt String { F em }
                            } {}
                            : Pt h @ Pt { ( arc_new [PtImpl] @ PtImpl { file tensors dims } ) }
                            ^ @ !Pt String { T h }
                        }
                    }
                }
            }
        }
    }
}

// mmap-backed where the platform has it (POSIX), a whole-file read where it
// does not (wasm, win32).
@ pt_open s path → !Pt String {
    ?? ( file_map path ) {
        T m → {
            ? < ( mapped_len m ) 22 { ^ ( __pt_errs `torchpt: file too small to be a zip archive` ) } {}
            ^ ( __pt_parse m )
        }
        F _ → {
            : String msg ( string_from `torchpt: cannot open ` )
            ( string_push_str msg path )
            ^ @ !Pt String { F msg }
        }
    }
}

// Let go of `p` now rather than at the end of its owner's scope; the last
// owner unmaps the checkpoint.
@ pt_close sink Pt p → v {}

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
@ __pt_elem_index PtImpl p PtTensor t i n → i {
    ? == . t contiguous 1 { ^ n } {}
    : i sh . t shape_at
    : ~ i rem n
    : ~ i off 0
    : ~ i j - . t ndim 1
    ~ >= j 0 {
        : i d ( vec_at [i] . p dims + sh j )
        ? > d 0 {
            = off + off * % rem d ( vec_at [i] . p dims + + sh 8 j )
            = rem / rem d
        } {}
        = j - j 1
    }
    ^ off
}

// One element at byte `off` of the mapping, as f32 bits.
@ __pt_elem_f32bits i dtype ( Slice u ) P i off → i {
    ? == dtype PKS_F32 { ^ ( slice_u32_le P off ) } {}
    ? == dtype PKS_F64 { ^ ( f32_to_bits # f32 ( bits_to_f64 ( slice_u64_le P off ) ) ) } {}
    ? == dtype PKS_F16 { ^ ( f16_bits_to_f32_bits ( slice_u16_le P off ) ) } {}
    ? == dtype PKS_BF16 { ^ ( bf16_bits_to_f32_bits ( slice_u16_le P off ) ) } {}
    ? == dtype PKS_I64 {
        : i raw ( slice_u64_le P off )
        ^ ( f32_to_bits # f32 # f raw )
    } {}
    ? == dtype PKS_I32 {
        : i raw ( slice_u32_le P off )
        ^ ( f32_to_bits # f32 # f ? >= raw 2147483648 - raw 4294967296 raw )
    } {}
    ? == dtype PKS_I16 {
        : i raw ( slice_u16_le P off )
        ^ ( f32_to_bits # f32 # f ? >= raw 32768 - raw 65536 raw )
    } {}
    ? == dtype PKS_I8 {
        : i raw # i ( slice_at [u] P off )
        ^ ( f32_to_bits # f32 # f ? >= raw 128 - raw 256 raw )
    } {}
    ? | == dtype PKS_U8 == dtype PKS_BOOL { ^ ( f32_to_bits # f32 # f # i ( slice_at [u] P off ) ) } {}
    ^ 0
}

@ pt_dequant_range Pt p__h i idx i first i count → !( Vec u ) String {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ? | < idx 0 >= idx ( vec_len [PtTensor] . p tensors ) { ^ ( __pt_err_vec `torchpt: tensor index out of range` ) } {}
    : PtTensor t ( vec_at [PtTensor] . p tensors idx )
    ? | | < first 0 < count 0 > + first count . t nelems {
        ^ ( __pt_err_vec `torchpt: element range outside the tensor` )
    } {}
    : i dtype . t dtype
    : i esize ( pk_storage_esize dtype )
    ? == esize 0 { ^ ( __pt_err_vec `torchpt: unsupported dtype` ) } {}
    : ( Slice u ) src ( mapped_bytes . p file )
    : i base . t data_off
    // F32 in storage order is the result's own bytes: one copy.
    ? & == dtype PKS_F32 == . t contiguous 1 {
        ^ @ !( Vec u ) String { T ( slice_to_vec [u] ( slice_window [u] src + base * first 4 * count 4 ) ) }
    } {}
    : ( Vec u ) out ( vec_zeroed [u] * count 4 )
    : ( Slice u ) q ( slice_from_vec [u] out )
    : ~ i j 0
    ~ < j count {
        ( slice_put_u32_le q * j 4 ( __pt_elem_f32bits dtype src + base * ( __pt_elem_index p t + first j ) esize ) )
        = j + j 1
    }
    ^ @ !( Vec u ) String { T out }
}

@ pt_dequant Pt p__h i idx → !( Vec u ) String {
    ^ ( pt_dequant_range p__h idx 0 ( pt_nelems p__h idx ) )
}

// Read `count` elements starting at `first` straight into `dst` (which
// must hold them) — the shape the tensor package wants, without a byte
// round-trip.
@ pt_read_f64_into Pt p__h i idx i first i count ( Slice f ) dst → b {
    : PtImpl p ( arc_get [PtImpl] . p__h a )
    ? | < idx 0 >= idx ( vec_len [PtTensor] . p tensors ) { ^ F } {}
    : PtTensor t ( vec_at [PtTensor] . p tensors idx )
    ? | | < first 0 < count 0 > + first count . t nelems { ^ F } {}
    : i dtype . t dtype
    : i esize ( pk_storage_esize dtype )
    ? == esize 0 { ^ F } {}
    : ( Slice u ) src ( mapped_bytes . p file )
    : ( Slice f ) out ( slice_prefix [f] dst count )
    : ~ i j 0
    ~ < j count {
        : i off + . t data_off * ( __pt_elem_index p t + first j ) esize
        // f64 storages keep their full precision; everything else is
        // exactly representable in f32 first.
        : f x ? == dtype PKS_F64 ( bits_to_f64 ( slice_u64_le src off ) )
        # f ( bits_to_f32 ( __pt_elem_f32bits dtype src off ) )
        ( slice_put [f] out j x )
        = j + j 1
    }
    ^ T
}

// The same into a raw buffer of `count` f64s. raw: the caller vouches for
// `dst`.
raw @ pt_read_f64 Pt p__h i idx i first i count * f dst → b {
    ^ ( pt_read_f64_into p__h idx first count ( slice_from_raw [f] dst count ) )
}
