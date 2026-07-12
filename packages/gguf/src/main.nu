// gguf — inspect, verify and export GGUF model containers.
//
//   gguf info <file>                  one-line summary
//   gguf dump <file>                  header + all metadata + tensors
//   gguf kv <file> <key>              print one metadata value
//   gguf tensors <file>               tensor table
//   gguf verify <file>                deep structural check (+ overlap)
//   gguf export <file> <tensor> -o out.f32    dequantise to f32-LE
//   gguf gen <out.gguf>               write the reference sample file
//   gguf selftest                     write → parse → compare, bit-exact
//
// The parser treats every input as hostile: malformed, truncated or
// adversarial files produce an error message, never a crash, hang or
// unbounded allocation (see tests/gguf_test.sh, which proves this
// with a corruption battery).

$ `stdlib/core/io.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/floatbits.nu`
$ `gguf.nu`
$ `dequant.nu`
$ `write.nu`

: i GGUF_CLI_VERSION_MAJOR 0

@ __gg_vt_name i vt → s {
    ? == vt 0 { ^ `u8` } {}
    ? == vt 1 { ^ `i8` } {}
    ? == vt 2 { ^ `u16` } {}
    ? == vt 3 { ^ `i16` } {}
    ? == vt 4 { ^ `u32` } {}
    ? == vt 5 { ^ `i32` } {}
    ? == vt 6 { ^ `f32` } {}
    ? == vt 7 { ^ `bool` } {}
    ? == vt 8 { ^ `str` } {}
    ? == vt 9 { ^ `arr` } {}
    ? == vt 10 { ^ `u64` } {}
    ? == vt 11 { ^ `i64` } {}
    ? == vt 12 { ^ `f64` } {}
    ^ `?`
}

// Render one KV as `key = <type> value` (arrays truncated to 8 elems).
@ __gg_fmt_kv GgufKv a → String {
    : String m ( string_from ( string_data . a key ) )
    ( string_push_str m ` = ` )
    : i vt . a vt
    ? == vt 8 {
        ( string_push_str m `str ` )
        ( string_push_str m ( string_data . a sval ) )
        ^ m
    } {}
    ? == vt 9 {
        ( string_push_str m `[` )
        ( string_push_str m ( __gg_vt_name . a atype ) )
        : ~ i n 0
        ? == . a atype 8 { = n ( vec_len [String] . a astr ) } {
            ? | == . a atype 6 == . a atype 12 { = n ( vec_len [f] . a af ) } {
                = n ( vec_len [i] . a ai )
            }
        }
        ( string_push_str m ` x ` )
        ( string_push_int m n )
        ( string_push_str m `]` )
        : ~ i k 0
        ~ & < k n < k 8 {
            ( string_push_str m ` ` )
            ? == . a atype 8 {
                ?? ( vec_get [String] . a astr k ) {
                    T sv → { ( string_push_str m ( string_data sv ) ) }
                    F → {}
                }
            } {
                ? | == . a atype 6 == . a atype 12 {
                    ?? ( vec_get [f] . a af k ) {
                        T x → { ( string_push_float m x ) }
                        F → {}
                    }
                } {
                    ?? ( vec_get [i] . a ai k ) {
                        T x → { ( string_push_int m x ) }
                        F → {}
                    }
                }
            }
            = k + k 1
        }
        ? > n 8 { ( string_push_str m ` …` ) } {}
        ^ m
    } {}
    ( string_push_str m ( __gg_vt_name vt ) )
    ( string_push_str m ` ` )
    ? | == vt 6 == vt 12 { ( string_push_float m . a fval ) } {
        ? == vt 7 { ( string_push_str m ? != . a ival 0 `true` `false` ) } {
            ( string_push_int m . a ival )
        }
    }
    ^ m
}

@ __gg_fmt_tensor GgufTensor t → String {
    : String m ( string_from ( string_data . t name ) )
    : ~ i pad - 40 ( string_len m )
    ~ > pad 0 {
        ( string_push_char m 32 )
        = pad - pad 1
    }
    ( string_push_str m ` ` )
    : s tn ( gguf_type_name . t gtype )
    ? ( nurl_str_eq tn `?` ) {
        ( string_push_str m `unknown(` )
        ( string_push_int m . t gtype )
        ( string_push_str m `)` )
    } {
        ( string_push_str m tn )
    }
    ( string_push_str m ` [` )
    ( string_push_int m . t d0 )
    ? >= . t nd 2 {
        ( string_push_str m ` ` )
        ( string_push_int m . t d1 )
    } {}
    ? >= . t nd 3 {
        ( string_push_str m ` ` )
        ( string_push_int m . t d2 )
    } {}
    ? >= . t nd 4 {
        ( string_push_str m ` ` )
        ( string_push_int m . t d3 )
    } {}
    ( string_push_str m `] ` )
    ? >= . t nbytes 0 { ( string_push_int m . t nbytes ) } { ( string_push_str m `?` ) }
    ( string_push_str m ` B @ ` )
    ( string_push_int m . t offset )
    ^ m
}

@ __gg_print_owned String m → v {
    ( nurl_print ( string_data m ) )
    ( nurl_print `\n` )
    ( string_free m )
}

@ __gg_err String e → i {
    ( nurl_eprintln ( string_data e ) )
    ( string_free e )
    ^ 1
}

@ __gg_info * Gguf g → v {
    : String m ( string_from `GGUF v` )
    ( string_push_int m ( gguf_version g ) )
    ( string_push_str m ` — ` )
    ( string_push_int m ( gguf_n_kv g ) )
    ( string_push_str m ` kv, ` )
    ( string_push_int m ( gguf_n_tensors g ) )
    ( string_push_str m ` tensors, align ` )
    ( string_push_int m ( gguf_align g ) )
    ( string_push_str m `, data ` )
    ( string_push_int m ( gguf_data_size g ) )
    ( string_push_str m ` B` )
    : s arch ( gguf_kv_str_or g `general.architecture` `` )
    ? > ( nurl_str_len arch ) 0 {
        ( string_push_str m `, arch ` )
        ( string_push_str m arch )
    } {}
    : s nm ( gguf_kv_str_or g `general.name` `` )
    ? > ( nurl_str_len nm ) 0 {
        ( string_push_str m `, name ` )
        ( string_push_str m nm )
    } {}
    ( __gg_print_owned m )
}

@ __gg_cmd_dump * Gguf g → v {
    ( __gg_info g )
    : ~ i k 0
    ~ < k ( gguf_n_kv g ) {
        ?? ( vec_get [GgufKv] . g kvs k ) {
            T a → { ( __gg_print_owned ( __gg_fmt_kv a ) ) }
            F → {}
        }
        = k + k 1
    }
    = k 0
    ~ < k ( gguf_n_tensors g ) {
        ?? ( vec_get [GgufTensor] . g tensors k ) {
            T t → { ( __gg_print_owned ( __gg_fmt_tensor t ) ) }
            F → {}
        }
        = k + k 1
    }
}

// Deep structural verify: parse invariants already held at open; add
// the pairwise overlap proof for every sizable tensor and count what
// could not be sized.
@ __gg_cmd_verify * Gguf g → i {
    : i nt ( gguf_n_tensors g )
    : ~ i unsized 0
    : ~ i k 0
    ~ < k nt {
        ?? ( vec_get [GgufTensor] . g tensors k ) {
            T t → { ? < . t nbytes 0 { = unsized + unsized 1 } {} }
            F → {}
        }
        = k + k 1
    }
    = k 0
    : ~ i ova -1
    : ~ i ovb -1
    ~ < k nt {
        ?? ( vec_get [GgufTensor] . g tensors k ) {
            T a → {
                ? < . a nbytes 0 {} {
                    : ~ i j + k 1
                    ~ < j nt {
                        ?? ( vec_get [GgufTensor] . g tensors j ) {
                            T b2 → {
                                ? < . b2 nbytes 0 {} {
                                    ? & < . a offset + . b2 offset . b2 nbytes < . b2 offset + . a offset . a nbytes {
                                        = ova k
                                        = ovb j
                                    } {}
                                }
                            }
                            F → {}
                        }
                        = j + j 1
                    }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ? >= ova 0 {
        : ~ String m ( string_from `gguf: OVERLAP — tensors ` )
        ?? ( vec_get [GgufTensor] . g tensors ova ) {
            T a → { ( string_push_str m ( string_data . a name ) ) }
            F → {}
        }
        ( string_push_str m ` and ` )
        ?? ( vec_get [GgufTensor] . g tensors ovb ) {
            T a → { ( string_push_str m ( string_data . a name ) ) }
            F → {}
        }
        ( string_push_str m ` share bytes in the data section` )
        ^ ( __gg_err m )
    } {}
    : String m ( string_from `OK — GGUF v` )
    ( string_push_int m ( gguf_version g ) )
    ( string_push_str m `, ` )
    ( string_push_int m ( gguf_n_kv g ) )
    ( string_push_str m ` kv, ` )
    ( string_push_int m nt )
    ( string_push_str m ` tensors` )
    ? > unsized 0 {
        ( string_push_str m ` (` )
        ( string_push_int m unsized )
        ( string_push_str m ` of unknown type not size-checked)` )
    } {}
    ( string_push_str m `, all offsets aligned, in-bounds and disjoint` )
    ( __gg_print_owned m )
    ^ 0
}

// ── the reference sample (gen + selftest) ───────────────────────────

@ __st_push_f32 ( Vec u ) v f x → v {
    ( bytes_push_u32_le v # u32 ( f32_to_bits # f32 x ) )
}

// Builds the reference sample: every KV type, and one tensor per
// dequantisable ggml type with hand-picked edge values (f16 subnormal,
// ±inf, NaN, negative quants).
@ __st_build → *GgufW {
    : ~ i waddr 0
    ?? ( gw_new 32 ) {
        T w2 → { = waddr # i w2 }
        F e → { ( string_free e ) }
    }
    : *GgufW w # *GgufW waddr
    ( gw_kv_str w `general.architecture` `selftest` )
    ( gw_kv_str w `general.name` `gguf reference sample` )
    ( gw_kv_u32 w `selftest.u32` 4000000000 )
    ( gw_kv_i32 w `selftest.i32` -12345 )
    ( gw_kv_u64 w `selftest.u64` 8589934592 )
    ( gw_kv_i64 w `selftest.i64` -8589934592 )
    ( gw_kv_f32 w `selftest.f32` 1.5 )
    ( gw_kv_f64 w `selftest.f64` -2.25 )
    ( gw_kv_bool w `selftest.bool_t` T )
    ( gw_kv_bool w `selftest.bool_f` F )
    : ( Vec i ) ai ( vec_new [i] )
    ( vec_push [i] ai 3 )
    ( vec_push [i] ai -7 )
    ( vec_push [i] ai 42 )
    ( gw_kv_arr_i32 w `selftest.arr_i32` ai )
    ( vec_free [i] ai )
    : ( Vec f ) af ( vec_new [f] )
    ( vec_push [f] af 0.5 )
    ( vec_push [f] af -2.25 )
    ( gw_kv_arr_f32 w `selftest.arr_f32` af )
    ( vec_free [f] af )
    : ( Vec String ) astr ( vec_new [String] )
    ( vec_push [String] astr ( string_from `alpha` ) )
    ( vec_push [String] astr ( string_from `beta` ) )
    ( vec_push [String] astr ( string_from `gamma` ) )
    ( gw_kv_arr_str w `selftest.arr_str` astr )
    ( vec_free_with [String] astr \ String s → v { ( string_free s ) } )

    // t_f32: 8 exactly-representable values
    : ( Vec u ) bf32 ( vec_new [u] )
    ( __st_push_f32 bf32 0.0 )
    ( __st_push_f32 bf32 1.5 )
    ( __st_push_f32 bf32 -2.25 )
    ( __st_push_f32 bf32 3.75 )
    ( __st_push_f32 bf32 100.0 )
    ( __st_push_f32 bf32 -0.0078125 )
    ( __st_push_f32 bf32 6.5 )
    ( __st_push_f32 bf32 -7.0 )
    : !v String r1 ( gw_tensor w `t_f32` 0 2 4 2 1 1 bf32 )
    ( vec_free [u] bf32 )
    ?? r1 { T _ → {} F e → { ( string_free e ) } }

    // t_f16: 9 bit-exact edge cases incl. subnormals, ±inf, NaN, -0
    : ( Vec u ) bf16 ( vec_new [u] )
    ( bytes_push_u16_le bf16 # u16 0 )
    ( bytes_push_u16_le bf16 # u16 15360 )
    ( bytes_push_u16_le bf16 # u16 49152 )
    ( bytes_push_u16_le bf16 # u16 1 )
    ( bytes_push_u16_le bf16 # u16 1023 )
    ( bytes_push_u16_le bf16 # u16 31744 )
    ( bytes_push_u16_le bf16 # u16 64512 )
    ( bytes_push_u16_le bf16 # u16 32256 )
    ( bytes_push_u16_le bf16 # u16 32768 )
    : !v String r2 ( gw_tensor w `t_f16` 1 1 9 1 1 1 bf16 )
    ( vec_free [u] bf16 )
    ?? r2 { T _ → {} F e → { ( string_free e ) } }

    // t_bf16: shift-up transport
    : ( Vec u ) bbf ( vec_new [u] )
    ( bytes_push_u16_le bbf # u16 16256 )
    ( bytes_push_u16_le bbf # u16 49152 )
    ( bytes_push_u16_le bbf # u16 0 )
    ( bytes_push_u16_le bbf # u16 32640 )
    : !v String r3 ( gw_tensor w `t_bf16` 30 1 4 1 1 1 bbf )
    ( vec_free [u] bbf )
    ?? r3 { T _ → {} F e → { ( string_free e ) } }

    // t_q4_0: one block, d = 1.0, qs[j] = j | (15-j)<<4
    : ( Vec u ) bq4 ( vec_new [u] )
    ( bytes_push_u16_le bq4 # u16 15360 )
    : ~ i j 0
    ~ < j 16 {
        ( vec_push [u] bq4 # u | j << - 15 j 4 )
        = j + j 1
    }
    : !v String r4 ( gw_tensor w `t_q4_0` 2 1 32 1 1 1 bq4 )
    ( vec_free [u] bq4 )
    ?? r4 { T _ → {} F e → { ( string_free e ) } }

    // t_q4_1: d = 1.0, m = -8.0 — must decode identically to t_q4_0
    : ( Vec u ) bq41 ( vec_new [u] )
    ( bytes_push_u16_le bq41 # u16 15360 )
    ( bytes_push_u16_le bq41 # u16 51200 )
    = j 0
    ~ < j 16 {
        ( vec_push [u] bq41 # u | j << - 15 j 4 )
        = j + j 1
    }
    : !v String r5 ( gw_tensor w `t_q4_1` 3 1 32 1 1 1 bq41 )
    ( vec_free [u] bq41 )
    ?? r5 { T _ → {} F e → { ( string_free e ) } }

    // t_q8_0: d = 0.5, q = 0..30 then -56
    : ( Vec u ) bq8 ( vec_new [u] )
    ( bytes_push_u16_le bq8 # u16 14336 )
    = j 0
    ~ < j 31 {
        ( vec_push [u] bq8 # u j )
        = j + j 1
    }
    ( vec_push [u] bq8 # u 200 )
    : !v String r6 ( gw_tensor w `t_q8_0` 8 1 32 1 1 1 bq8 )
    ( vec_free [u] bq8 )
    ?? r6 { T _ → {} F e → { ( string_free e ) } }
    ^ w
}

: STCnt {
    i pass
    i fail
}

@ __st_ck inout STCnt cn b ok s name → v {
    ? ok { = . cn pass + . cn pass 1 } {
        = . cn fail + . cn fail 1
        ( nurl_print `  FAIL ` )
        ( nurl_print name )
        ( nurl_print `\n` )
    }
}

// f64 vector equality against a raw expected pointer + count
@ __st_vec_eq ( Vec f ) got * f exp i n → b {
    ? != ( vec_len [f] got ) n { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ < k n {
        ?? ( vec_get [f] got k ) {
            T x → { ? == x . exp k {} { = ok F } }
            F → { = ok F }
        }
        = k + k 1
    }
    ^ ok
}

@ __st_run → i {
    : ~ STCnt cn @ STCnt { 0 0 }
    : *GgufW w ( __st_build )
    : !String IoErr tf ( fs_tempfile `/tmp` `gguf-selftest.` )
    : ~ String path ( string_new )
    ?? tf {
        T p → {
            ( string_free path )
            = path p
        }
        F _ → {
            ( nurl_eprintln `selftest: cannot create a temp file under /tmp` )
            ( gw_free w )
            ^ 1
        }
    }
    : !v String wr ( gw_write w ( string_data path ) )
    ( gw_free w )
    ?? wr {
        T _ → {}
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( file_delete ( string_data path ) )
            ( string_free path )
            ^ 1
        }
    }

    : !*Gguf String orr ( gguf_open ( string_data path ) )
    : ~ i rc 0
    ?? orr {
        T g → {
            ( __st_ck cn == ( gguf_version g ) 3 `version is 3` )
            ( __st_ck cn == ( gguf_align g ) 32 `alignment is 32` )
            ( __st_ck cn == ( gguf_n_kv g ) 14 `kv count` )
            ( __st_ck cn == ( gguf_n_tensors g ) 6 `tensor count` )
            ( __st_ck cn ( nurl_str_eq ( gguf_kv_str_or g `general.architecture` `` ) `selftest` ) `str kv` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.u32` 0 ) 4000000000 `u32 kv` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.i32` 0 ) -12345 `i32 kv (negative)` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.u64` 0 ) 8589934592 `u64 kv (> 32 bit)` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.i64` 0 ) -8589934592 `i64 kv (negative)` )
            ( __st_ck cn == ( gguf_kv_f_or g `selftest.f32` 0.0 ) 1.5 `f32 kv` )
            ( __st_ck cn == ( gguf_kv_f_or g `selftest.f64` 0.0 ) -2.25 `f64 kv` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.bool_t` 0 ) 1 `bool kv true` )
            ( __st_ck cn == ( gguf_kv_int_or g `selftest.bool_f` 1 ) 0 `bool kv false` )
            ( __st_ck cn == ( gguf_kv_int_or g `general.alignment` 0 ) 32 `alignment kv emitted` )
            ( __st_ck cn == ( gguf_kv_int_or g `no.such.key` -1 ) -1 `absent kv falls to default` )

            : i ai_idx ( gguf_find_kv g `selftest.arr_i32` )
            ( __st_ck cn >= ai_idx 0 `arr_i32 present` )
            ? >= ai_idx 0 {
                ?? ( vec_get [GgufKv] . g kvs ai_idx ) {
                    T a → {
                        ( __st_ck cn == ( vec_len [i] . a ai ) 3 `arr_i32 length` )
                        : ~ i v1 0
                        ?? ( vec_get [i] . a ai 1 ) { T x → { = v1 x } F → {} }
                        ( __st_ck cn == v1 -7 `arr_i32 negative element` )
                    }
                    F → {}
                }
            } {}
            : i as_idx ( gguf_find_kv g `selftest.arr_str` )
            ( __st_ck cn >= as_idx 0 `arr_str present` )
            ? >= as_idx 0 {
                ?? ( vec_get [GgufKv] . g kvs as_idx ) {
                    T a → {
                        ( __st_ck cn == ( vec_len [String] . a astr ) 3 `arr_str length` )
                        : ~ b ok F
                        ?? ( vec_get [String] . a astr 2 ) {
                            T sv → { = ok ( string_eq_raw sv `gamma` ) }
                            F → {}
                        }
                        ( __st_ck cn ok `arr_str element` )
                    }
                    F → {}
                }
            } {}

            // t_f32 round-trips bit-exactly
            : i tf32 ( gguf_find_tensor g `t_f32` )
            ( __st_ck cn >= tf32 0 `t_f32 present` )
            ? >= tf32 0 {
                ?? ( vec_get [GgufTensor] . g tensors tf32 ) {
                    T t → {
                        ( __st_ck cn & == . t nd 2 & == . t d0 4 == . t d1 2 `t_f32 dims` )
                        ( __st_ck cn == . t nelems 8 `t_f32 nelems` )
                        ( __st_ck cn == . t nbytes 32 `t_f32 nbytes` )
                    }
                    F → {}
                }
                : !( Vec f ) String dr ( gguf_dequant_f64 g tf32 )
                ?? dr {
                    T got → {
                        : f32exp [f | 0.0 1.5 -2.25 3.75 100.0 -0.0078125 6.5 -7.0]
                        ( __st_ck cn ( __st_vec_eq got . f32exp 0 8 ) `t_f32 dequant values` )
                        ( vec_free [f] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_f32 dequant` )
                    }
                }
            } {}

            // t_f16: IEEE edge table, bit-for-bit
            : i tf16 ( gguf_find_tensor g `t_f16` )
            ( __st_ck cn >= tf16 0 `t_f16 present` )
            ? >= tf16 0 {
                : !( Vec u ) String dr ( gguf_dequant g tf16 )
                ?? dr {
                    T got → {
                        : f16exp [i | 0 1065353216 3221225472 864026624 947896320 2139095040 4286578688 2143289344 2147483648]
                        : *i EP . f16exp 0
                        : ~ b ok == ( vec_len [u] got ) 36
                        : ~ i k 0
                        ~ < k 9 {
                            : ~ i gb -1
                            ?? ( bytes_read_u32_le got * k 4 ) {
                                T x → { = gb # i x }
                                F → {}
                            }
                            ? == gb . EP k {} { = ok F }
                            = k + k 1
                        }
                        ( __st_ck cn ok `t_f16 bit-exact (incl. subnormal/inf/NaN/-0)` )
                        ( vec_free [u] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_f16 dequant` )
                    }
                }
            } {}

            // t_bf16
            : i tbf ( gguf_find_tensor g `t_bf16` )
            ? >= tbf 0 {
                : !( Vec u ) String dr ( gguf_dequant g tbf )
                ?? dr {
                    T got → {
                        : bfexp [i | 1065353216 3221225472 0 2139095040]
                        : *i EP . bfexp 0
                        : ~ b ok == ( vec_len [u] got ) 16
                        : ~ i k 0
                        ~ < k 4 {
                            : ~ i gb -1
                            ?? ( bytes_read_u32_le got * k 4 ) {
                                T x → { = gb # i x }
                                F → {}
                            }
                            ? == gb . EP k {} { = ok F }
                            = k + k 1
                        }
                        ( __st_ck cn ok `t_bf16 bit-exact` )
                        ( vec_free [u] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_bf16 dequant` )
                    }
                }
            } { ( __st_ck cn F `t_bf16 present` ) }

            // t_q4_0: element k = k-8 (k<16), 7-(k-16) (k≥16)
            : i tq4 ( gguf_find_tensor g `t_q4_0` )
            : ( Vec f ) q4exp ( vec_new [f] )
            : ~ i k 0
            ~ < k 16 {
                ( vec_push [f] q4exp # f - k 8 )
                = k + k 1
            }
            = k 0
            ~ < k 16 {
                ( vec_push [f] q4exp # f - 7 k )
                = k + k 1
            }
            ? >= tq4 0 {
                : !( Vec f ) String dr ( gguf_dequant_f64 g tq4 )
                ?? dr {
                    T got → {
                        ( __st_ck cn ( __st_vec_eq got ( vec_data [f] q4exp ) 32 ) `t_q4_0 dequant values` )
                        ( vec_free [f] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_q4_0 dequant` )
                    }
                }
            } { ( __st_ck cn F `t_q4_0 present` ) }

            // t_q4_1 with d=1, m=-8 must equal t_q4_0
            : i tq41 ( gguf_find_tensor g `t_q4_1` )
            ? >= tq41 0 {
                : !( Vec f ) String dr ( gguf_dequant_f64 g tq41 )
                ?? dr {
                    T got → {
                        ( __st_ck cn ( __st_vec_eq got ( vec_data [f] q4exp ) 32 ) `t_q4_1 equals t_q4_0 (d=1, m=-8)` )
                        ( vec_free [f] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_q4_1 dequant` )
                    }
                }
            } { ( __st_ck cn F `t_q4_1 present` ) }
            ( vec_free [f] q4exp )

            // t_q8_0: 0.5*k, last = -28
            : i tq8 ( gguf_find_tensor g `t_q8_0` )
            ? >= tq8 0 {
                : !( Vec f ) String dr ( gguf_dequant_f64 g tq8 )
                ?? dr {
                    T got → {
                        : ( Vec f ) q8exp ( vec_new [f] )
                        = k 0
                        ~ < k 31 {
                            ( vec_push [f] q8exp * 0.5 # f k )
                            = k + k 1
                        }
                        ( vec_push [f] q8exp -28.0 )
                        ( __st_ck cn ( __st_vec_eq got ( vec_data [f] q8exp ) 32 ) `t_q8_0 dequant (incl. negative q)` )
                        ( vec_free [f] q8exp )
                        ( vec_free [f] got )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `t_q8_0 dequant` )
                    }
                }
            } { ( __st_ck cn F `t_q8_0 present` ) }

            // unknown tensor / bad index are clean errors
            ( __st_ck cn < ( gguf_find_tensor g `no_such_tensor` ) 0 `absent tensor → -1` )
            : !( Vec u ) String bad ( gguf_dequant g 99 )
            ?? bad {
                T got2 → {
                    ( vec_free [u] got2 )
                    ( __st_ck cn F `out-of-range dequant must fail` )
                }
                F e → {
                    ( string_free e )
                    ( __st_ck cn T `out-of-range dequant fails cleanly` )
                }
            }
            ( gguf_close g )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }

    // second path: parse the same image from an in-memory buffer
    ? == rc 0 {
        : !( Vec u ) IoErr br ( read_file_bytes ( string_data path ) )
        ?? br {
            T img → {
                : !*Gguf String pr ( gguf_parse_bytes img )
                ?? pr {
                    T g → {
                        ( __st_ck cn == ( gguf_n_tensors g ) 6 `parse_bytes sees the same tensors` )
                        ( gguf_close g )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn F `parse_bytes` )
                    }
                }
                // corrupt the magic in memory → must fail
                ( vec_set [u] img 0 # u 88 )
                : !*Gguf String cr ( gguf_parse_bytes img )
                ?? cr {
                    T g → {
                        ( gguf_close g )
                        ( __st_ck cn F `bad magic must be rejected` )
                    }
                    F e → {
                        ( string_free e )
                        ( __st_ck cn T `bad magic rejected` )
                    }
                }
                ( vec_free [u] img )
            }
            F _ → { ( __st_ck cn F `re-read sample file` ) }
        }
        // tiny buffer → clean error
        : ( Vec u ) tiny ( vec_new [u] )
        ( vec_push [u] tiny # u 71 )
        ( vec_push [u] tiny # u 71 )
        : !*Gguf String tr ( gguf_parse_bytes tiny )
        ?? tr {
            T g → {
                ( gguf_close g )
                ( __st_ck cn F `truncated buffer must be rejected` )
            }
            F e → {
                ( string_free e )
                ( __st_ck cn T `truncated buffer rejected` )
            }
        }
        ( vec_free [u] tiny )
    } {}

    ( file_delete ( string_data path ) )
    ( string_free path )
    ? != rc 0 { ^ rc } {}
    : String m ( string_from `selftest: ` )
    ( string_push_int m . cn pass )
    ( string_push_str m ` passed, ` )
    ( string_push_int m . cn fail )
    ( string_push_str m ` failed` )
    ( __gg_print_owned m )
    ^ ? > . cn fail 0 1 0
}

// String vs raw-literal equality (helper for selftest)
@ string_eq_raw String a s raw → b {
    ^ ? ( nurl_str_eq ( string_data a ) raw ) T F
}

@ main → i {
    : ArgParser p ( args_new `gguf` `Inspect, verify and export GGUF model containers (parser treats every file as untrusted input).` )
    ( args_opt p `output` 111 `FILE` `for export: write the f32-LE tensor here` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  info <file> · dump <file> · kv <file> <key> · tensors <file>\n  verify <file> · export <file> <tensor> -o out.f32\n  gen <out.gguf> · selftest\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print `gguf 0.1.0\n` )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: gguf <info|dump|kv|tensors|verify|export|gen|selftest> … (gguf --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) {
        T c → { = cmd ( string_data c ) }
        F → {}
    }
    : ~ String a1 ( string_new )
    ? >= ( args_positional_count p ) 2 {
        ?? ( vec_get [String] pos 1 ) {
            T v2 → {
                ( string_free a1 )
                = a1 ( string_from ( string_data v2 ) )
            }
            F → {}
        }
    } {}
    : ~ String a2 ( string_new )
    ? >= ( args_positional_count p ) 3 {
        ?? ( vec_get [String] pos 2 ) {
            T v2 → {
                ( string_free a2 )
                = a2 ( string_from ( string_data v2 ) )
            }
            F → {}
        }
    } {}

    ? ( nurl_str_eq cmd `selftest` ) {
        : i rc ( __st_run )
        ( string_free a1 )
        ( string_free a2 )
        ( args_free p )
        ^ rc
    } {}

    ? ( nurl_str_eq cmd `gen` ) {
        ? == ( string_len a1 ) 0 {
            ( string_free a1 )
            ( string_free a2 )
            ( args_free p )
            ^ ( __gg_err ( string_from `gguf: gen needs an output path` ) )
        } {}
        : *GgufW w ( __st_build )
        : !v String wr ( gw_write w ( string_data a1 ) )
        ( gw_free w )
        : ~ i rc 0
        ?? wr {
            T _ → {}
            F e → { = rc ( __gg_err e ) }
        }
        ( string_free a1 )
        ( string_free a2 )
        ( args_free p )
        ^ rc
    } {}

    // every remaining command opens a file first
    ? == ( string_len a1 ) 0 {
        ( string_free a1 )
        ( string_free a2 )
        ( args_free p )
        ^ ( __gg_err ( string_from `gguf: this command needs a file argument (gguf --help)` ) )
    } {}
    : !*Gguf String orr ( gguf_open ( string_data a1 ) )
    : ~ i rc 0
    ?? orr {
        T g → {
            ? ( nurl_str_eq cmd `info` ) {
                ( __gg_info g )
            } {
                ? ( nurl_str_eq cmd `dump` ) {
                    ( __gg_cmd_dump g )
                } {
                    ? ( nurl_str_eq cmd `tensors` ) {
                        : ~ i k 0
                        ~ < k ( gguf_n_tensors g ) {
                            ?? ( vec_get [GgufTensor] . g tensors k ) {
                                T t → { ( __gg_print_owned ( __gg_fmt_tensor t ) ) }
                                F → {}
                            }
                            = k + k 1
                        }
                    } {
                        ? ( nurl_str_eq cmd `verify` ) {
                            = rc ( __gg_cmd_verify g )
                        } {
                            ? ( nurl_str_eq cmd `kv` ) {
                                : i idx ( gguf_find_kv g ( string_data a2 ) )
                                ? < idx 0 {
                                    = rc ( __gg_err ( string_from `gguf: no such metadata key` ) )
                                } {
                                    ?? ( vec_get [GgufKv] . g kvs idx ) {
                                        T a → { ( __gg_print_owned ( __gg_fmt_kv a ) ) }
                                        F → {}
                                    }
                                }
                            } {
                                ? ( nurl_str_eq cmd `export` ) {
                                    : i idx ( gguf_find_tensor g ( string_data a2 ) )
                                    ? < idx 0 {
                                        = rc ( __gg_err ( string_from `gguf: no such tensor` ) )
                                    } {
                                        : !( Vec u ) String dr ( gguf_dequant g idx )
                                        ?? dr {
                                            T raw → {
                                                : ?String oo ( args_value p `output` )
                                                ?? oo {
                                                    T out → {
                                                        : !v IoErr wr2 ( write_file_bytes ( string_data out ) raw )
                                                        ?? wr2 {
                                                            T _ → {
                                                                : String m ( string_from `wrote ` )
                                                                ( string_push_int m ( vec_len [u] raw ) )
                                                                ( string_push_str m ` bytes of f32-LE` )
                                                                ( __gg_print_owned m )
                                                            }
                                                            F _ → { = rc ( __gg_err ( string_from `gguf: cannot write the output file` ) ) }
                                                        }
                                                        ( string_free out )
                                                    }
                                                    F → { = rc ( __gg_err ( string_from `gguf: export needs -o FILE` ) ) }
                                                }
                                                ( vec_free [u] raw )
                                            }
                                            F e → { = rc ( __gg_err e ) }
                                        }
                                    }
                                } {
                                    ( nurl_eprintln `gguf: unknown command (gguf --help)` )
                                    = rc 2
                                }
                            }
                        }
                    }
                }
            }
            ( gguf_close g )
        }
        F e → { = rc ( __gg_err e ) }
    }
    ( string_free a1 )
    ( string_free a2 )
    ( args_free p )
    ^ rc
}
