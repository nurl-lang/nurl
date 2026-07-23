// packages/safetensor/src/write.nu — the safetensors WRITER (the round-trip
// partner of safetensor.nu's reader). The format is small:
//
//     u64 LE header_len
//     header_len bytes of JSON   { "name":{dtype,shape,data_offsets:[a,b]}, … }
//     the tensor bytes           (a,b are offsets INTO this region)
//
// A writer accumulates tensors (each appends its bytes and one header entry
// with contiguous, sorted-by-insertion data_offsets), then stw_finish emits
// the whole file: u64 header length, the JSON, then the concatenated data.
// The offsets are contiguous and gap-free by construction, which is what the
// reference `safetensors` library requires; st_open reads it back exactly.
//
// Typed adds convert f64 HOST values to the on-disk dtype: F64/F32 exact,
// F16/BF16 via floatbits' encoders (the same ones gguf uses); I64 from a
// host i vector. stw_add_raw takes pre-encoded bytes for any other dtype.
//
//   ( stw_new )                          → *StWriter
//   ( stw_add_f32 w name shape v )       → v        (v: Vec f, host f64)
//   ( stw_add_f64 w name shape v )       → v
//   ( stw_add_f16 w name shape v )       → v
//   ( stw_add_bf16 w name shape v )      → v
//   ( stw_add_i64 w name shape v )       → v        (v: Vec i)
//   ( stw_add_raw w name dtype shape b ) → v        (b: Vec u, LE bytes)
//   ( stw_finish w )                     → ( Vec u ) — the whole file
//   ( stw_write w path )                 → !v String
//   ( stw_free w )                       → v

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `safetensor.nu`

@ __stw_gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ __stw_gi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → x F → 0 } }

: StWriter {
    String hdr  // building JSON, starts "{"
    ( Vec u ) data  // concatenated tensor bytes
    b first  // no comma before the first entry
}

@ stw_new → *StWriter {
    : *StWriter w # *StWriter ( nurl_alloc Z StWriter )
    = . w hdr ( string_from `{` )
    = . w data ( vec_new [u] )
    = . w first T
    ^ w
}

// Append the JSON header entry for a tensor whose bytes already sit in
// . w data at [at, endo).
@ __stw_entry * StWriter w s name i dtype ( Vec i ) shape i at i endo → v {
    ? . w first { = . w first F } { ( string_push_str . w hdr `,` ) }
    ( string_push_str . w hdr `"` )
    ( string_push_str . w hdr name )
    ( string_push_str . w hdr `":{"dtype":"` )
    ( string_push_str . w hdr ( st_dtype_name dtype ) )
    ( string_push_str . w hdr `","shape":[` )
    : ~ i j 0
    ~ < j ( vec_len [i] shape ) {
        ? > j 0 { ( string_push_str . w hdr `,` ) } {}
        ( string_push_str . w hdr ( nurl_str_int ( __stw_gi shape j ) ) )
        = j + j 1
    }
    ( string_push_str . w hdr `],"data_offsets":[` )
    ( string_push_str . w hdr ( nurl_str_int at ) )
    ( string_push_str . w hdr `,` )
    ( string_push_str . w hdr ( nurl_str_int endo ) )
    ( string_push_str . w hdr `]}` )
}

// Any dtype: `bytes` is the tensor's raw little-endian payload.
@ stw_add_raw * StWriter w s name i dtype ( Vec i ) shape ( Vec u ) bytes → v {
    : i at ( vec_len [u] . w data )
    ( bytes_extend_bytes . w data bytes )
    : i endo ( vec_len [u] . w data )
    ( __stw_entry w name dtype shape at endo )
}

// F32: host f64 rounded to float32 on write.
@ stw_add_f32 * StWriter w s name ( Vec i ) shape ( Vec f ) v → v {
    : i at ( vec_len [u] . w data )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( bytes_push_f32_le . w data # f32 ( __stw_gf v k ) )
        = k + k 1
    }
    ( __stw_entry w name ST_F32 shape at ( vec_len [u] . w data ) )
}

// F64: host f64 exact.
@ stw_add_f64 * StWriter w s name ( Vec i ) shape ( Vec f ) v → v {
    : i at ( vec_len [u] . w data )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( bytes_push_f64_le . w data ( __stw_gf v k ) )
        = k + k 1
    }
    ( __stw_entry w name ST_F64 shape at ( vec_len [u] . w data ) )
}

// F16: host f64 → IEEE half (round-to-nearest-even via floatbits).
@ stw_add_f16 * StWriter w s name ( Vec i ) shape ( Vec f ) v → v {
    : i at ( vec_len [u] . w data )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( bytes_push_u16_le . w data # u16 ( f_to_f16 ( __stw_gf v k ) ) )
        = k + k 1
    }
    ( __stw_entry w name ST_F16 shape at ( vec_len [u] . w data ) )
}

// BF16: host f64 → bfloat16 (truncated top 16 bits of the f32).
@ stw_add_bf16 * StWriter w s name ( Vec i ) shape ( Vec f ) v → v {
    : i at ( vec_len [u] . w data )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ( bytes_push_u16_le . w data # u16 ( f_to_bf16 ( __stw_gf v k ) ) )
        = k + k 1
    }
    ( __stw_entry w name ST_BF16 shape at ( vec_len [u] . w data ) )
}

// I64 from a host i vector.
@ stw_add_i64 * StWriter w s name ( Vec i ) shape ( Vec i ) v → v {
    : i at ( vec_len [u] . w data )
    : ~ i k 0
    ~ < k ( vec_len [i] v ) {
        ( bytes_push_u64_le . w data # u64 ( __stw_gi v k ) )
        = k + k 1
    }
    ( __stw_entry w name ST_I64 shape at ( vec_len [u] . w data ) )
}

// The whole file as one byte vector.
@ stw_finish * StWriter w → ( Vec u ) {
    ( string_push_str . w hdr `}` )
    : i hlen ( string_len . w hdr )
    : ( Vec u ) out ( vec_new [u] )
    ( bytes_push_u64_le out # u64 hlen )
    : ~ i k 0
    ~ < k hlen {
        ( vec_push [u] out ( nurl_str_get ( string_data . w hdr ) k ) )
        = k + k 1
    }
    ( bytes_extend_bytes out . w data )
    ^ out
}

@ stw_write * StWriter w s path → !v String {
    : ( Vec u ) out ( stw_finish w )
    : ~ b wok T
    ?? ( write_file_bytes path out ) {
        T _ → {}
        F _ → { = wok F }
    }
    ( vec_free [u] out )
    ? wok { ^ @ !v String { T } }
    ^ @ !v String { F ( string_from `safetensor: cannot write file` ) }
}

@ stw_free * StWriter w → v {
    ( string_free . w hdr )
    ( vec_free [u] . w data )
    ( nurl_free # s w )
}
