// packages/lingbot-map/src/weights.nu — the checkpoint, as the model
// wants to see it.
//
// `torchpt` gives an mmap and a name→(dtype, shape, bytes) table. What
// the model wants is "give me `aggregator.frame_blocks.7.attn.qkv.weight`,
// and fail loudly if it is not 3072×1024". This is that, and nothing
// more: no device buffers, no transposition, no caching — those belong
// with whoever is building a layer, which knows what layout it needs.
//
// Names are checked, not assumed. A checkpoint whose layer count or
// hidden size differs from what the caller expects produces a message
// naming the tensor and both shapes, at load time, instead of a wrong
// answer several hundred matmuls later.
//
//   ( lw_open path )                     → !*Lw String
//   ( lw_close w )                       → v
//   ( lw_has w name )                    → b
//   ( lw_index w name )                  → i    -1 when absent
//   ( lw_dim w name axis )               → i
//   ( lw_nelems w name )                 → i
//   ( lw_read w name dst n )             → b    f64 into a caller buffer
//   ( lw_require w name d0 d1 d2 d3 )    → b    shape check; −1 = any
//   ( lw_error w )                       → s    first failure, "" if none
//
// `lw_require` accumulates: call it for every tensor a module needs,
// then read `lw_error` once. That way a mismatched checkpoint reports
// the first thing that is wrong rather than the first thing that is
// read.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/torchpt/src/torchpt.nu`

: Lw {
    * Pt pt
    ( Vec String ) errs
}

@ lw_open s path → !*Lw String {
    : !*Pt String r ( pt_open path )
    ?? r {
        F e → ^ @ !*Lw String { F e }
        T pt → {
            : *Lw w # *Lw ( nurl_alloc Z Lw )
            = . w pt pt
            = . w errs ( vec_new [String] )
            ^ @ !*Lw String { T w }
        }
    }
}

@ lw_close * Lw w → v {
    ( pt_close . w pt )
    ( vec_free_with [String] . w errs \ String s → v { ( string_free s ) } )
    ( nurl_free # s w )
}

@ lw_n_tensors * Lw w → i { ^ ( pt_n_tensors . w pt ) }

@ lw_index * Lw w s name → i { ^ ( pt_find . w pt name ) }

@ lw_has * Lw w s name → b { ^ >= ( pt_find . w pt name ) 0 }

@ lw_ndim * Lw w s name → i {
    : i i0 ( pt_find . w pt name )
    ? < i0 0 { ^ 0 } {}
    ^ ( pt_ndim . w pt i0 )
}

@ lw_dim * Lw w s name i axis → i {
    : i i0 ( pt_find . w pt name )
    ? < i0 0 { ^ 0 } {}
    ^ ( pt_dim . w pt i0 axis )
}

@ lw_nelems * Lw w s name → i {
    : i i0 ( pt_find . w pt name )
    ? < i0 0 { ^ 0 } {}
    ^ ( pt_nelems . w pt i0 )
}

@ __lw_fail * Lw w String m → v {
    ? == 0 ( vec_len [String] . w errs ) { ( vec_push [String] . w errs m ) }
    { ( string_free m ) }
}

@ lw_error * Lw w → s {
    ?? ( vec_get [String] . w errs 0 ) { T s → ^ ( string_data s ) F → ^ `` }
}

@ lw_ok * Lw w → b { ^ == 0 ( vec_len [String] . w errs ) }

// Read a whole tensor into a caller-owned f64 buffer of at least
// `n` elements. Records a failure and returns F if the tensor is absent,
// the wrong size, or unreadable.
@ lw_read * Lw w s name * f dst i n → b {
    : i i0 ( pt_find . w pt name )
    ? < i0 0 {
        : String m ( string_from `lingbot-map: checkpoint has no tensor '` )
        ( string_push_str m name )
        ( string_push_char m 39 )
        ( __lw_fail w m )
        ^ F
    } {}
    : i have ( pt_nelems . w pt i0 )
    ? != have n {
        : String m ( string_from `lingbot-map: '` )
        ( string_push_str m name )
        ( string_push_str m `' has ` )
        ( string_push_int m have )
        ( string_push_str m ` elements, expected ` )
        ( string_push_int m n )
        ( __lw_fail w m )
        ^ F
    } {}
    ? ! ( pt_read_f64 . w pt i0 0 n dst ) {
        : String m ( string_from `lingbot-map: cannot read '` )
        ( string_push_str m name )
        ( string_push_str m `' (unsupported dtype?)` )
        ( __lw_fail w m )
        ^ F
    } {}
    ^ T
}

// Assert a tensor's presence and shape. Pass −1 for an axis that may be
// anything, and for axes beyond the tensor's rank. Records the first
// failure; returns whether THIS check passed.
@ lw_require * Lw w s name i d0 i d1 i d2 i d3 → b {
    : i i0 ( pt_find . w pt name )
    ? < i0 0 {
        : String m ( string_from `lingbot-map: checkpoint has no tensor '` )
        ( string_push_str m name )
        ( string_push_char m 39 )
        ( __lw_fail w m )
        ^ F
    } {}
    : i want ? >= d3 0 4 ? >= d2 0 3 ? >= d1 0 2 ? >= d0 0 1 0
    : i nd ( pt_ndim . w pt i0 )
    ? & > want 0 != nd want {
        : String m ( string_from `lingbot-map: '` )
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
        : i got ( pt_dim . w pt i0 ax )
        ? & >= want_ax 0 != got want_ax {
            : String m ( string_from `lingbot-map: '` )
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
@ lw_count_indexed * Lw w s prefix s suffix → i {
    : ~ i n 0
    : ~ b more T
    ~ & more < n 4096 {
        : String nm ( string_from prefix )
        ( string_push_int nm n )
        ( string_push_str nm suffix )
        ? ( lw_has w ( string_data nm ) ) { = n + n 1 } { = more F }
        ( string_free nm )
    }
    ^ n
}
