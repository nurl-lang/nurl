// packages/gguf/src/write.nu — a GGUF v3 writer/builder.
//
// The reader's round-trip partner: build typed metadata and tensors in
// memory, then serialise a spec-exact GGUF v3 image. Powers the test
// suite (write → parse → compare, bit for bit) and gives the ecosystem
// an export path (tensor snapshots, converted models, fixtures).
//
//   ( gw_new align )                       → !*GgufW String
//   ( gw_kv_u32 w key v )  ( gw_kv_i32 … ) ( gw_kv_u64 … )
//   ( gw_kv_f32 w key x )  ( gw_kv_f64 … ) ( gw_kv_bool … )
//   ( gw_kv_str w key val )
//   ( gw_kv_arr_i32 w key vals )           — ( Vec i ),   borrowed
//   ( gw_kv_arr_f32 w key vals )           — ( Vec f ),   borrowed
//   ( gw_kv_arr_str w key vals )           — ( Vec String ), borrowed
//   ( gw_tensor w name gt nd d0 d1 d2 d3 bytes ) → !v String
//   ( gw_finish w )                        → ( Vec u )   the file image
//   ( gw_write w path )                    → !v String
//   ( gw_free w )
//
// gw_new emits `general.alignment` itself (so the image is
// self-describing) — callers must not add that key again.
// gw_tensor validates the payload length against the declared
// type/dims and pads the data section to the alignment, exactly as
// the parser will demand on the way back in.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `gguf.nu`

: GgufW {
    i align
    i n_kv
    ( Vec u ) kvb
    ( Vec String ) tnames
    ( Vec i ) ttype
    ( Vec i ) tnd
    ( Vec i ) td0
    ( Vec i ) td1
    ( Vec i ) td2
    ( Vec i ) td3
    ( Vec i ) toff
    ( Vec u ) data
}

// length-prefixed GGUF string: u64 LE length + raw bytes (no NUL)
@ __gw_pstr ( Vec u ) b s raw → v {
    ( bytes_push_u64_le b # u64 ( nurl_str_len raw ) )
    ( bytes_extend_str b raw )
}

@ __gw_key ( Vec u ) b s key i vt → v {
    ( __gw_pstr b key )
    ( bytes_push_u32_le b # u32 vt )
}

@ gw_new i align → !*GgufW String {
    ? | | < align 1 > align 1048576 != & align - align 1 0 {
        ^ @ !*GgufW String { F ( string_from `gguf: writer alignment must be a power of two, 1..1048576` ) }
    } {}
    : *GgufW w # *GgufW ( nurl_alloc Z GgufW )
    = . w align align
    = . w n_kv 0
    = . w kvb ( vec_new [u] )
    = . w tnames ( vec_new [String] )
    = . w ttype ( vec_new [i] )
    = . w tnd ( vec_new [i] )
    = . w td0 ( vec_new [i] )
    = . w td1 ( vec_new [i] )
    = . w td2 ( vec_new [i] )
    = . w td3 ( vec_new [i] )
    = . w toff ( vec_new [i] )
    = . w data ( vec_new [u] )
    ( gw_kv_u32 w `general.alignment` align )
    ^ @ !*GgufW String { T w }
}

@ gw_kv_u32 * GgufW w s key i v → v {
    ( __gw_key . w kvb key 4 )
    ( bytes_push_u32_le . w kvb # u32 v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_i32 * GgufW w s key i v → v {
    ( __gw_key . w kvb key 5 )
    ( bytes_push_u32_le . w kvb # u32 & v 4294967295 )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_u64 * GgufW w s key i v → v {
    ( __gw_key . w kvb key 10 )
    ( bytes_push_u64_le . w kvb # u64 v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_i64 * GgufW w s key i v → v {
    ( __gw_key . w kvb key 11 )
    ( bytes_push_u64_le . w kvb # u64 v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_f32 * GgufW w s key f x → v {
    ( __gw_key . w kvb key 6 )
    ( bytes_push_u32_le . w kvb # u32 ( f32_to_bits # f32 x ) )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_f64 * GgufW w s key f x → v {
    ( __gw_key . w kvb key 12 )
    ( bytes_push_u64_le . w kvb # u64 ( f64_to_bits x ) )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_bool * GgufW w s key b v → v {
    ( __gw_key . w kvb key 7 )
    ( vec_push [u] . w kvb # u ? v 1 0 )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_str * GgufW w s key s val → v {
    ( __gw_key . w kvb key 8 )
    ( __gw_pstr . w kvb val )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_i32 * GgufW w s key ( Vec i ) vals → v {
    ( __gw_key . w kvb key 9 )
    ( bytes_push_u32_le . w kvb # u32 5 )
    ( bytes_push_u64_le . w kvb # u64 ( vec_len [i] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [i] vals ) {
        ?? ( vec_get [i] vals k ) {
            T v → { ( bytes_push_u32_le . w kvb # u32 & v 4294967295 ) }
            F → {}
        }
        = k + k 1
    }
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_f32 * GgufW w s key ( Vec f ) vals → v {
    ( __gw_key . w kvb key 9 )
    ( bytes_push_u32_le . w kvb # u32 6 )
    ( bytes_push_u64_le . w kvb # u64 ( vec_len [f] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [f] vals ) {
        ?? ( vec_get [f] vals k ) {
            T v → { ( bytes_push_u32_le . w kvb # u32 ( f32_to_bits # f32 v ) ) }
            F → {}
        }
        = k + k 1
    }
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_str * GgufW w s key ( Vec String ) vals → v {
    ( __gw_key . w kvb key 9 )
    ( bytes_push_u32_le . w kvb # u32 8 )
    ( bytes_push_u64_le . w kvb # u64 ( vec_len [String] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [String] vals ) {
        ?? ( vec_get [String] vals k ) {
            T v → { ( __gw_pstr . w kvb ( string_data v ) ) }
            F → {}
        }
        = k + k 1
    }
    = . w n_kv + . w n_kv 1
}

// Add a tensor: validates the declared shape against the payload size
// with the same rules the parser enforces, aligns the data section,
// and records the entry. Unused trailing dims pass 1.
@ gw_tensor * GgufW w s name i gt i nd i d0 i d1 i d2 i d3 ( Vec u ) bytes → !v String {
    ? | < nd 1 > nd 4 {
        ^ @ !v String { F ( string_from `gguf: tensor n_dims must be 1..4` ) }
    } {}
    ? | | | < d0 1 < d1 1 < d2 1 < d3 1 {
        ^ @ !v String { F ( string_from `gguf: tensor dims must be ≥ 1` ) }
    } {}
    : i blk ( gguf_type_blck gt )
    ? == blk 0 {
        ^ @ !v String { F ( string_from `gguf: writer cannot size this tensor type` ) }
    } {}
    ? != % d0 blk 0 {
        ^ @ !v String { F ( string_from `gguf: dim0 must be a multiple of the type's block size` ) }
    } {}
    : i ne * * * d0 d1 d2 d3
    : i nb * / ne blk ( gguf_type_size gt )
    ? != nb ( vec_len [u] bytes ) {
        : String m ( string_from `gguf: tensor payload is ` )
        ( string_push_int m ( vec_len [u] bytes ) )
        ( string_push_str m ` bytes but the declared shape needs ` )
        ( string_push_int m nb )
        ^ @ !v String { F m }
    } {}
    : ~ i k 0
    : ~ b dup F
    ~ < k ( vec_len [String] . w tnames ) {
        ?? ( vec_get [String] . w tnames k ) {
            T t → { ? ( nurl_str_eq ( string_data t ) name ) { = dup T } {} }
            F → {}
        }
        = k + k 1
    }
    ? dup {
        ^ @ !v String { F ( string_from `gguf: duplicate tensor name in writer` ) }
    } {}
    // pad data to alignment, then append
    ~ != % ( vec_len [u] . w data ) . w align 0 {
        ( vec_push [u] . w data # u 0 )
    }
    ( vec_push [i] . w toff ( vec_len [u] . w data ) )
    ( vec_extend [u] . w data bytes )
    ( vec_push [String] . w tnames ( string_from name ) )
    ( vec_push [i] . w ttype gt )
    ( vec_push [i] . w tnd nd )
    ( vec_push [i] . w td0 d0 )
    ( vec_push [i] . w td1 d1 )
    ( vec_push [i] . w td2 d2 )
    ( vec_push [i] . w td3 d3 )
    ^ @ !v String { T 0 }
}

@ __gw_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// Serialise the complete GGUF v3 image.
@ gw_finish * GgufW w → ( Vec u ) {
    : i nt ( vec_len [String] . w tnames )
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 71 )
    ( vec_push [u] out # u 71 )
    ( vec_push [u] out # u 85 )
    ( vec_push [u] out # u 70 )
    ( bytes_push_u32_le out # u32 3 )
    ( bytes_push_u64_le out # u64 nt )
    ( bytes_push_u64_le out # u64 . w n_kv )
    ( vec_extend [u] out . w kvb )
    : ~ i k 0
    ~ < k nt {
        ?? ( vec_get [String] . w tnames k ) {
            T t → { ( __gw_pstr out ( string_data t ) ) }
            F → {}
        }
        : i nd ( __gw_geti . w tnd k )
        ( bytes_push_u32_le out # u32 nd )
        ( bytes_push_u64_le out # u64 ( __gw_geti . w td0 k ) )
        ? >= nd 2 { ( bytes_push_u64_le out # u64 ( __gw_geti . w td1 k ) ) } {}
        ? >= nd 3 { ( bytes_push_u64_le out # u64 ( __gw_geti . w td2 k ) ) } {}
        ? >= nd 4 { ( bytes_push_u64_le out # u64 ( __gw_geti . w td3 k ) ) } {}
        ( bytes_push_u32_le out # u32 ( __gw_geti . w ttype k ) )
        ( bytes_push_u64_le out # u64 ( __gw_geti . w toff k ) )
        = k + k 1
    }
    ~ != % ( vec_len [u] out ) . w align 0 {
        ( vec_push [u] out # u 0 )
    }
    ( vec_extend [u] out . w data )
    ^ out
}

@ gw_write * GgufW w s path → !v String {
    : ( Vec u ) img ( gw_finish w )
    : !v IoErr r ( write_file_bytes path img )
    ( vec_free [u] img )
    ?? r {
        T _ → { ^ @ !v String { T 0 } }
        F _ → {
            : String m ( string_from `gguf: cannot write ` )
            ( string_push_str m path )
            ^ @ !v String { F m }
        }
    }
}

@ gw_free * GgufW w → v {
    ( vec_free [u] . w kvb )
    ( vec_free_with [String] . w tnames \ String s → v { ( string_free s ) } )
    ( vec_free [i] . w ttype )
    ( vec_free [i] . w tnd )
    ( vec_free [i] . w td0 )
    ( vec_free [i] . w td1 )
    ( vec_free [i] . w td2 )
    ( vec_free [i] . w td3 )
    ( vec_free [i] . w toff )
    ( vec_free [u] . w data )
    ( nurl_free # s w )
}
