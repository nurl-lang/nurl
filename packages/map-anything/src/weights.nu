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
//   ( lw_read w name dst n )             → b    f64 into a caller view
//   ( lw_f32_bytes w name n )            → ( Slice u )   zero-copy when already f32
//   ( lw_require w name d0 d1 d2 d3 )    → b    shape check; −1 = any
//   ( lw_error w )                       → String   first failure, "" if none
//
// `lw_require` accumulates: call it for every tensor a module needs,
// then read `lw_error` once. That way a mismatched checkpoint reports
// the first thing that is wrong rather than the first thing that is
// read.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/safetensor/src/safetensor.nu`

// An open checkpoint is a handle: every copy is the same mapping (the
// St, whose last owner unmaps it) and the same record of failures, which
// any copy may add to. lw_close is an optional early release.
: Lw {
    St st
    ( Locked ( Vec String ) ) errs  // the first failure, once there is one
}

@ Lw_share Lw h → Lw { ^ @ Lw { ( St_share . h st ) ( Locked_share [( Vec String )] . h errs ) } }

@ Lw_drop sink Lw h → v {}

@ lw_open s path → !Lw String {
    : !St String r ( st_open path )
    ?? r {
        F e → ^ @ !Lw String { F e }
        T st → { ^ @ !Lw String { T @ Lw { st ( locked_new [( Vec String )] ( vec_new [String] ) ) } } }
    }
}

// Release the checkpoint now (optional — its last owner does it anyway).
@ lw_close sink Lw w → v {}

@ lw_n_tensors Lw w → i { ^ ( st_n_tensors . w st ) }

@ lw_index Lw w s name → i { ^ ( st_find_tensor . w st name ) }

@ lw_has Lw w s name → b { ^ >= ( st_find_tensor . w st name ) 0 }

@ lw_ndim Lw w s name → i {
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) { T t → ^ . t nd F → ^ 0 }
}

@ lw_dim Lw w s name i axis → i {
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
        T t → ^ ? == axis 0 . t d0 ? == axis 1 . t d1 ? == axis 2 . t d2 ? == axis 3 . t d3 0
        F → ^ 0
    }
}

@ lw_nelems Lw w s name → i {
    : i i0 ( st_find_tensor . w st name )
    ? < i0 0 { ^ 0 } {}
    ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) { T t → ^ . t nelems F → ^ 0 }
}

// Keep the first failure only; a later one is dropped with the call.
@ __lw_fail Lw w sink String m → v {
    : ( Vec String ) e ( locked_take [( Vec String )] . w errs )
    ? == 0 ( vec_len [String] e ) { ( vec_push [String] e m ) } {}
    ( locked_restore [( Vec String )] . w errs e )
}

// The first failure ('' if none), a copy of its own.
@ lw_error Lw w → String {
    : ( Vec String ) e ( locked_take [( Vec String )] . w errs )
    : ~ String out ( string_new )
    ?? ( vec_get [String] e 0 ) { T s → { = out ( string_from ( string_data s ) ) } F → {} }
    ( locked_restore [( Vec String )] . w errs e )
    ^ out
}

@ lw_ok Lw w → b {
    : ( Vec String ) e ( locked_take [( Vec String )] . w errs )
    : b ok == 0 ( vec_len [String] e )
    ( locked_restore [( Vec String )] . w errs e )
    ^ ok
}

// The tensor's own bytes inside the mapping, when they are already
// contiguous float32 — which is the layout a GK_F32 device buffer wants,
// so it can be uploaded with no conversion at all (gk_dbuf_upload_bytes).
// safetensors tensors are contiguous by construction, so only the dtype
// and length are checked: empty when the tensor is absent, a different
// dtype or a different length, and the caller falls back to the
// converting read. The view lives no longer than `w`.
@ lw_f32_bytes Lw w s name i n → ( Slice u ) {
    : i i0 ( st_find_tensor . w st name )
    ? >= i0 0 {
        ?? ( vec_get [StTensor] ( st_tensors . w st ) i0 ) {
            T t → { ? & == . t dtype ST_F32 == . t nelems n { ^ ( st_tensor_bytes . w st t ) } {} }
            F → {}
        }
    } {}
    ^ ( slice_of_str `` )
}

// Read a whole tensor into a caller-owned f64 view of at least `n`
// elements. Records a failure and returns F if the tensor is absent,
// the wrong size, or unreadable. Every dtype widens through f32 (the
// container's dequant path), which is exact for this checkpoint — the
// file is F32 throughout.
@ lw_read Lw w s name ( Slice f ) dst i n → b {
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
            : ( Slice u ) bv ( slice_from_vec [u] bytes )
            : ( Slice f ) dv ( slice_prefix [f] dst n )
            : ~ i k 0
            ~ < k n {
                ( slice_put [f] dv k # f ( bits_to_f32 # i ( slice_u32_le bv * k 4 ) ) )
                = k + k 1
            }
            ^ T
        }
    }
}

// Assert a tensor's presence and shape. Pass −1 for an axis that may be
// anything, and for axes beyond the tensor's rank. Records the first
// failure; returns whether THIS check passed.
@ lw_require Lw w s name i d0 i d1 i d2 i d3 → b {
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
