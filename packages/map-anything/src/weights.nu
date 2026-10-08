// packages/map-anything/src/weights.nu — the checkpoint, as the model
// wants to see it.
//
// Same surface as lingbot-map's weights.nu, but the container is
// safetensors (facebook/map-anything-apache ships a single
// model.safetensors, all F32), so `safetensor` provides the mmap and the
// name→(dtype, shape, bytes) table. What the model wants is "give me
// `info_sharing.model.layers.7.attn.qkv.weight`, and fail loudly if it
// is not 4608×1536". This is that, and nothing more: no device buffers,
// no transposition, no caching — those belong with whoever is building a
// layer, which knows what layout it needs.
//
// Names are checked, not assumed. A checkpoint whose layer count or
// hidden size differs from what the caller expects produces a message
// naming the tensor and both shapes, at load time, instead of a wrong
// answer several hundred matmuls later.
//
//   ( lw_open path )                     → !Lw String
//   ( lw_close w )                       → v    early release (optional)
//   ( lw_has w name )                    → b
//   ( lw_index w name )                  → i    -1 when absent
//   ( lw_dim w name axis )               → i
//   ( lw_nelems w name )                 → i
//   ( lw_read w name dst n )             → b    f64 into a caller buffer
//   ( lw_f32_ptr w name n )              → *u   zero-copy when already f32
//   ( lw_require w name d0 d1 d2 d3 )    → b    shape check; −1 = any
//   ( lw_error w )                       → s    first failure, "" if none
//
// `lw_require` accumulates: call it for every tensor a module needs,
// then read `lw_error` once. That way a mismatched checkpoint reports
// the first thing that is wrong rather than the first thing that is
// read.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/safetensor/src/safetensor.nu`

: LwImpl {
    St st  // the mapping: its last owner unmaps it
    ( Vec String ) errs
}

// An open checkpoint is a handle: every copy is the same mapping, and the
// last owner releases it. lw_close is an optional early release.
: Lw { s ctl }

unsafe @ Lw_share Lw h → Lw { ^ @ Lw { # s ( rcbox_share # i . h ctl ) } }

@ Lw_drop sink Lw h → v { ( mem_forget h ) ( rcbox_release [LwImpl] # i . h ctl ) }

unsafe @ __Lw_ptr Lw h → *LwImpl { ^ ( rcbox_ptr [LwImpl] # i . h ctl ) }
// No checkpoint (an empty slot until lw_open fills it).
@ lw_none → Lw { ^ @ Lw { # s 0 } }

unsafe @ lw_open s path → !Lw String {
    : !St String r ( st_open path )
    ?? r {
        F e → ^ @ !Lw String { F e }
        T st → { ^ @ !Lw String { T @ Lw { # s ( rcbox_new [LwImpl] @ LwImpl { st ( vec_new [String] ) } ) } } }
    }
}

// Release the checkpoint now (optional — its last owner does it anyway).
@ lw_close sink Lw w → v {}

unsafe @ lw_n_tensors Lw w__h → i { : *LwImpl w ( __Lw_ptr w__h ) ^ ( st_n_tensors . w st ) }

unsafe @ lw_index Lw w__h s name → i { : *LwImpl w ( __Lw_ptr w__h ) ^ ( st_find_tensor . w st name ) }

unsafe @ lw_has Lw w__h s name → b { : *LwImpl w ( __Lw_ptr w__h ) ^ >= ( st_find_tensor . w st name ) 0 }

unsafe @ lw_ndim Lw w__h s name → i {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) { T t → ^ . t nd F → ^ 0 }
}

unsafe @ lw_dim Lw w__h s name i axis → i {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
        T t → ^ ? == axis 0 . t d0 ? == axis 1 . t d1 ? == axis 2 . t d2 ? == axis 3 . t d3 0
        F → ^ 0
    }
}

unsafe @ lw_nelems Lw w__h s name → i {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) { T t → ^ . t nelems F → ^ 0 }
}

// Keep the first failure only; a later one is dropped with the call.
unsafe @ __lw_fail * LwImpl w sink String m → v {
    ? == 0 ( vec_len [String] . w errs ) { ( vec_push [String] . w errs m ) } {}
}

unsafe @ lw_error Lw w__h → s {
    : *LwImpl w ( __Lw_ptr w__h )
    ?? ( vec_get [String] . w errs 0 ) { T s → ^ ( string_data s ) F → ^ `` }
}

unsafe @ lw_ok Lw w__h → b { : *LwImpl w ( __Lw_ptr w__h ) ^ == 0 ( vec_len [String] . w errs ) }

// The tensor's own bytes inside the mapping, when they are already
// contiguous float32 — which is the layout a GK_F32 device buffer wants,
// so it can be uploaded with no conversion at all. safetensors tensors
// are contiguous by construction, so only the dtype and length are
// checked. Returns 0 when the tensor is absent, a different dtype or a
// different length, and the caller falls back to the converting read.
unsafe @ lw_f32_ptr Lw w__h s name i n → *u {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ # *u 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
        T t → {
            ? == . t dtype ST_F32 {} { ^ # *u 0 }
            ? == . t nelems n {} { ^ # *u 0 }
            ^ ( st_tensor_ptr . w st t )
        }
        F → ^ # *u 0
    }
}

// Read a whole tensor into a caller-owned f64 buffer of at least
// `n` elements. Records a failure and returns F if the tensor is absent,
// the wrong size, or unreadable. Every dtype widens through f32 (the
// container's dequant path), which is exact for this checkpoint — the
// file is F32 throughout.
unsafe @ lw_read Lw w__h s name * f dst i n → b {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 {
        : String m ( string_from `map-anything: checkpoint has no tensor '` )
        ( string_push_str m name )
        ( string_push_char m 39 )
        ( __lw_fail w m )
        ^ F
    } {}
    : ~ i have 0
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
        T t → { = have . t nelems }
        F → {}
    }
    ? != have n {
        : String m ( string_from `map-anything: '` )
        ( string_push_str m name )
        ( string_push_str m `' has ` )
        ( string_push_int m have )
        ( string_push_str m ` elements, expected ` )
        ( string_push_int m n )
        ( __lw_fail w m )
        ^ F
    } {}
    : !( Vec u ) String r ( st_dequant_range . w st i0 0 n )
    ?? r {
        F e → {
            : String m ( string_from `map-anything: cannot read '` )
            ( string_push_str m name )
            ( string_push_str m `': ` )
            ( string_push_str m ( string_data e ) )
            ( __lw_fail w m )
            ^ F
        }
        T bytes → {
            : *u p ( vec_data [u] bytes )
            : ~ i k 0
            ~ < k n {
                : i o * k 4
                : i bits | # i . p o | << # i . p + o 1 8 | << # i . p + o 2 16 << # i . p + o 3 24
                = . dst k # f ( bits_to_f32 bits )
                = k + k 1
            }
            ^ T
        }
    }
}

// Assert a tensor's presence and shape. Pass −1 for an axis that may be
// anything, and for axes beyond the tensor's rank. Records the first
// failure; returns whether THIS check passed.
unsafe @ lw_require Lw w__h s name i d0 i d1 i d2 i d3 → b {
    : *LwImpl w ( __Lw_ptr w__h )
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 {
        : String m ( string_from `map-anything: checkpoint has no tensor '` )
        ( string_push_str m name )
        ( string_push_char m 39 )
        ( __lw_fail w m )
        ^ F
    } {}
    : i want ? >= d3 0 4 ? >= d2 0 3 ? >= d1 0 2 ? >= d0 0 1 0
    : ~ i nd 0
    : ~ i g0 0
    : ~ i g1 0
    : ~ i g2 0
    : ~ i g3 0
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
        T t → {
            = nd . t nd
            = g0 . t d0
            = g1 . t d1
            = g2 . t d2
            = g3 . t d3
        }
        F → {}
    }
    ? & > want 0 != nd want {
        : String m ( string_from `map-anything: '` )
        ( string_push_str m name )
        ( string_push_str m `' is ` )
        ( string_push_int m nd )
        ( string_push_str m `-D, expected ` )
        ( string_push_int m want )
        ( string_push_str m `-D` )
        ( __lw_fail w m )
        ^ F
    } {}
    : ~ b ok T
    : ~ i ax 0
    ~ < ax want {
        : i want_ax ? == ax 0 d0 ? == ax 1 d1 ? == ax 2 d2 d3
        : i got ? == ax 0 g0 ? == ax 1 g1 ? == ax 2 g2 g3
        ? & >= want_ax 0 != got want_ax {
            : String m ( string_from `map-anything: '` )
            ( string_push_str m name )
            ( string_push_str m `' axis ` )
            ( string_push_int m ax )
            ( string_push_str m ` is ` )
            ( string_push_int m got )
            ( string_push_str m `, expected ` )
            ( string_push_int m want_ax )
            ( __lw_fail w m )
            = ok F
        } {}
        = ax + ax 1
    }
    ^ ok
}

// How many `<prefix>N<suffix>` tensors the checkpoint holds, counting up
// from 0 until one is missing — the layer count, read off the file
// rather than hard-coded.
@ lw_count_indexed Lw w__h s prefix s suffix → i {
    : ~ i n 0
    : ~ b more T
    ~ & more < n 4096 {
        : String nm ( string_from prefix )
        ( string_push_int nm n )
        ( string_push_str nm suffix )
        ? ( lw_has w__h ( string_data nm ) ) { = n + n 1 } { = more F }
    }
    ^ n
}
