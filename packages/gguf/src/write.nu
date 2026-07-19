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
//
// ── The STREAMING writer ────────────────────────────────────────────
// gw_* builds the whole image in memory — fine for fixtures, wrong for
// a multi-gigabyte model conversion on a machine whose RAM the model
// exceeds. The gws_* twin writes straight to a file in three phases:
// declare every KV and tensor (name/type/shape only), then
// gws_begin_data serialises the header + metadata + tensor table (all
// offsets are computable from the declarations alone), then payloads
// stream in DECLARATION ORDER through gws_data — any chunking, even
// byte at a time — and gws_finish verifies nothing is missing.
// Memory stays at the metadata + one caller chunk, whatever the file
// size.
//
//   ( gws_create path align )   → !*GgufS String
//   ( gws_kv_u32 s key v ) …          same KV family as gw_kv_*
//   ( gws_tensor s name gt nd d0 d1 d2 d3 ) → !v String
//   ( gws_begin_data s )        → !v String
//   ( gws_data s bytes )        → !v String   next payload bytes
//   ( gws_finish s )            → !v String   all payloads complete?
//   ( gws_free s )                            close + free (any phase)

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

// The KV encoders write into a bare byte buffer so the in-memory and
// streaming writers share one serialisation — the two front ends only
// differ in where the buffer eventually goes.
@ __gwkv_u32 ( Vec u ) kvb s key i v → v {
    ( __gw_key kvb key 4 )
    ( bytes_push_u32_le kvb # u32 v )
}

@ __gwkv_i32 ( Vec u ) kvb s key i v → v {
    ( __gw_key kvb key 5 )
    ( bytes_push_u32_le kvb # u32 & v 4294967295 )
}

@ __gwkv_u64 ( Vec u ) kvb s key i v → v {
    ( __gw_key kvb key 10 )
    ( bytes_push_u64_le kvb # u64 v )
}

@ __gwkv_i64 ( Vec u ) kvb s key i v → v {
    ( __gw_key kvb key 11 )
    ( bytes_push_u64_le kvb # u64 v )
}

@ __gwkv_f32 ( Vec u ) kvb s key f x → v {
    ( __gw_key kvb key 6 )
    ( bytes_push_u32_le kvb # u32 ( f32_to_bits # f32 x ) )
}

@ __gwkv_f64 ( Vec u ) kvb s key f x → v {
    ( __gw_key kvb key 12 )
    ( bytes_push_u64_le kvb # u64 ( f64_to_bits x ) )
}

@ __gwkv_bool ( Vec u ) kvb s key b v → v {
    ( __gw_key kvb key 7 )
    ( vec_push [u] kvb # u ? v 1 0 )
}

@ __gwkv_str ( Vec u ) kvb s key s val → v {
    ( __gw_key kvb key 8 )
    ( __gw_pstr kvb val )
}

@ __gwkv_arr_i32 ( Vec u ) kvb s key ( Vec i ) vals → v {
    ( __gw_key kvb key 9 )
    ( bytes_push_u32_le kvb # u32 5 )
    ( bytes_push_u64_le kvb # u64 ( vec_len [i] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [i] vals ) {
        ?? ( vec_get [i] vals k ) {
            T v → { ( bytes_push_u32_le kvb # u32 & v 4294967295 ) }
            F → {}
        }
        = k + k 1
    }
}

@ __gwkv_arr_f32 ( Vec u ) kvb s key ( Vec f ) vals → v {
    ( __gw_key kvb key 9 )
    ( bytes_push_u32_le kvb # u32 6 )
    ( bytes_push_u64_le kvb # u64 ( vec_len [f] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [f] vals ) {
        ?? ( vec_get [f] vals k ) {
            T v → { ( bytes_push_u32_le kvb # u32 ( f32_to_bits # f32 v ) ) }
            F → {}
        }
        = k + k 1
    }
}

@ __gwkv_arr_str ( Vec u ) kvb s key ( Vec String ) vals → v {
    ( __gw_key kvb key 9 )
    ( bytes_push_u32_le kvb # u32 8 )
    ( bytes_push_u64_le kvb # u64 ( vec_len [String] vals ) )
    : ~ i k 0
    ~ < k ( vec_len [String] vals ) {
        ?? ( vec_get [String] vals k ) {
            T v → { ( __gw_pstr kvb ( string_data v ) ) }
            F → {}
        }
        = k + k 1
    }
}

@ gw_kv_u32 * GgufW w s key i v → v {
    ( __gwkv_u32 . w kvb key v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_i32 * GgufW w s key i v → v {
    ( __gwkv_i32 . w kvb key v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_u64 * GgufW w s key i v → v {
    ( __gwkv_u64 . w kvb key v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_i64 * GgufW w s key i v → v {
    ( __gwkv_i64 . w kvb key v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_f32 * GgufW w s key f x → v {
    ( __gwkv_f32 . w kvb key x )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_f64 * GgufW w s key f x → v {
    ( __gwkv_f64 . w kvb key x )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_bool * GgufW w s key b v → v {
    ( __gwkv_bool . w kvb key v )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_str * GgufW w s key s val → v {
    ( __gwkv_str . w kvb key val )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_i32 * GgufW w s key ( Vec i ) vals → v {
    ( __gwkv_arr_i32 . w kvb key vals )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_f32 * GgufW w s key ( Vec f ) vals → v {
    ( __gwkv_arr_f32 . w kvb key vals )
    = . w n_kv + . w n_kv 1
}

@ gw_kv_arr_str * GgufW w s key ( Vec String ) vals → v {
    ( __gwkv_arr_str . w kvb key vals )
    = . w n_kv + . w n_kv 1
}

// Byte size the declared shape demands, or the validation error —
// the same rules the parser enforces. Shared by both writers.
@ __gw_tensor_bytes i gt i nd i d0 i d1 i d2 i d3 → !i String {
    ? | < nd 1 > nd 4 {
        ^ @ !i String { F ( string_from `gguf: tensor n_dims must be 1..4` ) }
    } {}
    ? | | | < d0 1 < d1 1 < d2 1 < d3 1 {
        ^ @ !i String { F ( string_from `gguf: tensor dims must be ≥ 1` ) }
    } {}
    : i blk ( gguf_type_blck gt )
    ? == blk 0 {
        ^ @ !i String { F ( string_from `gguf: writer cannot size this tensor type` ) }
    } {}
    ? != % d0 blk 0 {
        ^ @ !i String { F ( string_from `gguf: dim0 must be a multiple of the type's block size` ) }
    } {}
    : i ne * * * d0 d1 d2 d3
    ^ @ !i String { T * / ne blk ( gguf_type_size gt ) }
}

@ __gw_has_name ( Vec String ) tnames s name → b {
    : ~ i k 0
    : ~ b dup F
    ~ < k ( vec_len [String] tnames ) {
        ?? ( vec_get [String] tnames k ) {
            T t → { ? ( nurl_str_eq ( string_data t ) name ) { = dup T } {} }
            F → {}
        }
        = k + k 1
    }
    ^ dup
}

// Add a tensor: validates the declared shape against the payload size
// with the same rules the parser enforces, aligns the data section,
// and records the entry. Unused trailing dims pass 1.
@ gw_tensor * GgufW w s name i gt i nd i d0 i d1 i d2 i d3 ( Vec u ) bytes → !v String {
    : ~ i nb -1
    ?? ( __gw_tensor_bytes gt nd d0 d1 d2 d3 ) {
        T n → { = nb n }
        F e → { ^ @ !v String { F e } }
    }
    ? != nb ( vec_len [u] bytes ) {
        : String m ( string_from `gguf: tensor payload is ` )
        ( string_push_int m ( vec_len [u] bytes ) )
        ( string_push_str m ` bytes but the declared shape needs ` )
        ( string_push_int m nb )
        ^ @ !v String { F m }
    } {}
    ? ( __gw_has_name . w tnames name ) {
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

// ── streaming writer ────────────────────────────────────────────────

: GgufS {
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
    ( Vec i ) tbytes
    s fh
    // 0 = declaring KVs and tensors, 1 = streaming payloads, 2 = finished
    i phase
    i cur
    i cur_got
    i data_pos
    i data_size
}

@ __gws_err s msg → !v String {
    ^ @ !v String { F ( string_from msg ) }
}

@ gws_create s path i align → !*GgufS String {
    ? | | < align 1 > align 1048576 != & align - align 1 0 {
        ^ @ !*GgufS String { F ( string_from `gguf: writer alignment must be a power of two, 1..1048576` ) }
    } {}
    ?? ( file_create path ) {
        T fh → {
            : *GgufS s # *GgufS ( nurl_alloc Z GgufS )
            = . s align align
            = . s n_kv 0
            = . s kvb ( vec_new [u] )
            = . s tnames ( vec_new [String] )
            = . s ttype ( vec_new [i] )
            = . s tnd ( vec_new [i] )
            = . s td0 ( vec_new [i] )
            = . s td1 ( vec_new [i] )
            = . s td2 ( vec_new [i] )
            = . s td3 ( vec_new [i] )
            = . s toff ( vec_new [i] )
            = . s tbytes ( vec_new [i] )
            = . s fh . fh raw
            = . s phase 0
            = . s cur 0
            = . s cur_got 0
            = . s data_pos 0
            = . s data_size 0
            ( gws_kv_u32 s `general.alignment` align )
            ^ @ !*GgufS String { T s }
        }
        F _ → {
            : String m ( string_from `gguf: cannot create ` )
            ( string_push_str m path )
            ^ @ !*GgufS String { F m }
        }
    }
}

@ gws_kv_u32 * GgufS s s key i v → v {
    ( __gwkv_u32 . s kvb key v )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_i32 * GgufS s s key i v → v {
    ( __gwkv_i32 . s kvb key v )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_u64 * GgufS s s key i v → v {
    ( __gwkv_u64 . s kvb key v )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_i64 * GgufS s s key i v → v {
    ( __gwkv_i64 . s kvb key v )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_f32 * GgufS s s key f x → v {
    ( __gwkv_f32 . s kvb key x )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_f64 * GgufS s s key f x → v {
    ( __gwkv_f64 . s kvb key x )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_bool * GgufS s s key b v → v {
    ( __gwkv_bool . s kvb key v )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_str * GgufS s s key s val → v {
    ( __gwkv_str . s kvb key val )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_arr_i32 * GgufS s s key ( Vec i ) vals → v {
    ( __gwkv_arr_i32 . s kvb key vals )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_arr_f32 * GgufS s s key ( Vec f ) vals → v {
    ( __gwkv_arr_f32 . s kvb key vals )
    = . s n_kv + . s n_kv 1
}

@ gws_kv_arr_str * GgufS s s key ( Vec String ) vals → v {
    ( __gwkv_arr_str . s kvb key vals )
    = . s n_kv + . s n_kv 1
}

// Round `x` up to the writer's alignment.
@ __gws_align_up * GgufS s i x → i {
    : i r % x . s align
    ^ ? == r 0 x + x - . s align r
}

// Declare a tensor: shape only — the payload streams in later, in
// declaration order. The data-section offset is fixed here, which is
// what lets the whole tensor table serialise before any payload byte
// exists.
@ gws_tensor * GgufS s s name i gt i nd i d0 i d1 i d2 i d3 → !v String {
    ? != . s phase 0 { ^ ( __gws_err `gguf: streaming writer is past its declare phase` ) } {}
    : ~ i nb -1
    ?? ( __gw_tensor_bytes gt nd d0 d1 d2 d3 ) {
        T n → { = nb n }
        F e → { ^ @ !v String { F e } }
    }
    ? ( __gw_has_name . s tnames name ) {
        ^ ( __gws_err `gguf: duplicate tensor name in writer` )
    } {}
    : i off ( __gws_align_up s . s data_size )
    ( vec_push [String] . s tnames ( string_from name ) )
    ( vec_push [i] . s ttype gt )
    ( vec_push [i] . s tnd nd )
    ( vec_push [i] . s td0 d0 )
    ( vec_push [i] . s td1 d1 )
    ( vec_push [i] . s td2 d2 )
    ( vec_push [i] . s td3 d3 )
    ( vec_push [i] . s toff off )
    ( vec_push [i] . s tbytes nb )
    = . s data_size + off nb
    ^ @ !v String { T 0 }
}

@ __gws_write * GgufS s ( Vec u ) bytes → !v String {
    ?? ( file_write_chunk @ File { . s fh } bytes ) {
        T _ → { ^ @ !v String { T 0 } }
        F _ → { ^ ( __gws_err `gguf: file write failed` ) }
    }
}

// Write `n` zero bytes (alignment padding) to the file.
@ __gws_pad * GgufS s i n → !v String {
    ? <= n 0 { ^ @ !v String { T 0 } } {}
    : ( Vec u ) z ( vec_new [u] )
    : ~ i k 0
    ~ < k n {
        ( vec_push [u] z # u 0 )
        = k + k 1
    }
    : !v String r ( __gws_write s z )
    ( vec_free [u] z )
    ^ r
}

// Serialise the header, every KV and the whole tensor table, pad to
// the alignment, and switch to the payload phase.
@ gws_begin_data * GgufS s → !v String {
    ? != . s phase 0 { ^ ( __gws_err `gguf: streaming writer is past its declare phase` ) } {}
    : i nt ( vec_len [String] . s tnames )
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 71 )
    ( vec_push [u] out # u 71 )
    ( vec_push [u] out # u 85 )
    ( vec_push [u] out # u 70 )
    ( bytes_push_u32_le out # u32 3 )
    ( bytes_push_u64_le out # u64 nt )
    ( bytes_push_u64_le out # u64 . s n_kv )
    ( vec_extend [u] out . s kvb )
    : ~ i k 0
    ~ < k nt {
        ?? ( vec_get [String] . s tnames k ) {
            T t → { ( __gw_pstr out ( string_data t ) ) }
            F → {}
        }
        : i nd ( __gw_geti . s tnd k )
        ( bytes_push_u32_le out # u32 nd )
        ( bytes_push_u64_le out # u64 ( __gw_geti . s td0 k ) )
        ? >= nd 2 { ( bytes_push_u64_le out # u64 ( __gw_geti . s td1 k ) ) } {}
        ? >= nd 3 { ( bytes_push_u64_le out # u64 ( __gw_geti . s td2 k ) ) } {}
        ? >= nd 4 { ( bytes_push_u64_le out # u64 ( __gw_geti . s td3 k ) ) } {}
        ( bytes_push_u32_le out # u32 ( __gw_geti . s ttype k ) )
        ( bytes_push_u64_le out # u64 ( __gw_geti . s toff k ) )
        = k + k 1
    }
    ~ != % ( vec_len [u] out ) . s align 0 {
        ( vec_push [u] out # u 0 )
    }
    : !v String r ( __gws_write s out )
    ( vec_free [u] out )
    ?? r {
        T _ → {}
        F e → { ^ @ !v String { F e } }
    }
    = . s phase 1
    ^ @ !v String { T 0 }
}

// Payload bytes for the current tensor, any chunking. When a tensor's
// declared size is reached the writer advances to the next declared
// tensor (inserting the alignment gap first). Overrun is an error.
@ gws_data * GgufS s ( Vec u ) bytes → !v String {
    ? != . s phase 1 { ^ ( __gws_err `gguf: streaming writer is not in its data phase` ) } {}
    : i nt ( vec_len [String] . s tnames )
    ? >= . s cur nt { ^ ( __gws_err `gguf: payload bytes after the last declared tensor` ) } {}
    : i want ( __gw_geti . s tbytes . s cur )
    : i len ( vec_len [u] bytes )
    ? > + . s cur_got len want {
        : String m ( string_from `gguf: tensor payload overruns its declared size (tensor #` )
        ( string_push_int m . s cur )
        ( string_push_str m `)` )
        ^ @ !v String { F m }
    } {}
    // First byte of this tensor: pad the file up to its aligned offset.
    ? == . s cur_got 0 {
        : !v String pr ( __gws_pad s - ( __gw_geti . s toff . s cur ) . s data_pos )
        ?? pr {
            T _ → { = . s data_pos ( __gw_geti . s toff . s cur ) }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    ?? ( __gws_write s bytes ) {
        T _ → {}
        F e → { ^ @ !v String { F e } }
    }
    = . s cur_got + . s cur_got len
    = . s data_pos + . s data_pos len
    ? == . s cur_got want {
        = . s cur + . s cur 1
        = . s cur_got 0
    } {}
    ^ @ !v String { T 0 }
}

// All payloads in? Flush and close. The handle is closed here (not in
// gws_free) so the caller sees the failure, not a silent short file.
@ gws_finish * GgufS s → !v String {
    ? != . s phase 1 { ^ ( __gws_err `gguf: streaming writer is not in its data phase` ) } {}
    : i nt ( vec_len [String] . s tnames )
    ? < . s cur nt {
        : String m ( string_from `gguf: tensor #` )
        ( string_push_int m . s cur )
        ( string_push_str m ` never received its payload` )
        ^ @ !v String { F m }
    } {}
    : ~ b flush_ok F
    ?? ( file_flush @ File { . s fh } ) {
        T _ → { = flush_ok T }
        F _ → {}
    }
    ( file_close @ File { . s fh } )
    = . s fh # s 0
    = . s phase 2
    ? flush_ok {} { ^ ( __gws_err `gguf: file flush failed` ) }
    ^ @ !v String { T 0 }
}

@ gws_free * GgufS s → v {
    ? != 0 # i . s fh { ( file_close @ File { . s fh } ) } {}
    ( vec_free [u] . s kvb )
    ( vec_free_with [String] . s tnames \ String t → v { ( string_free t ) } )
    ( vec_free [i] . s ttype )
    ( vec_free [i] . s tnd )
    ( vec_free [i] . s td0 )
    ( vec_free [i] . s td1 )
    ( vec_free [i] . s td2 )
    ( vec_free [i] . s td3 )
    ( vec_free [i] . s toff )
    ( vec_free [i] . s tbytes )
    ( nurl_free # s s )
}
