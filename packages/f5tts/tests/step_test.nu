// step_test.nu — one guided step, split into its two halves.
//
// The single-sample forward already matches the reference. This checks the
// two-sample classifier-free-guidance forward: the conditional half, the
// unconditional half, and the guided velocity they combine into.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `src/model.nu`
$ `src/sample.nu`

: ~ i g_fail 0

@ __s_path s dir s name → String {
    : String p ( string_from dir ) ( string_push_char p 47 ) ( string_push_str p name ) ^ p
}

@ __s_read_f32 s dir s name → ( Vec f ) {
    : String p ( __s_path dir name )
    : ( Vec f ) out ( vec_new [f] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n { ?? ( bytes_read_f32_le bs * k 4 ) { T x → { ( vec_push [f] out # f x ) } F → {} } = k + k 1 }
            ( vec_free [u] bs )
        }
        F _e → { ( nurl_eprint `cannot read ` ) ( nurl_eprintln ( string_data p ) ) }
    }
    ( string_free p ) ^ out
}

@ __s_read_i32 s dir s name → ( Vec i ) {
    : String p ( __s_path dir name )
    : ( Vec i ) out ( vec_new [i] )
    ?? ( read_file_bytes ( string_data p ) ) {
        T bs → {
            : i n / ( vec_len [u] bs ) 4
            : ~ i k 0
            ~ < k n { ?? ( bytes_read_u32_le bs * k 4 ) { T x → { ( vec_push [i] out # i x ) } F → {} } = k + k 1 }
            ( vec_free [u] bs )
        }
        F _e → {}
    }
    ( string_free p ) ^ out
}

@ __s_get ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } } }

@ __s_cmp ( Vec f ) got i off ( Vec f ) want s label → v {
    : i n ( vec_len [f] want )
    : ~ f md 0.0
    : ~ f mx 1.0e-12
    : ~ i k 0
    ~ < k n {
        : f w ( __s_get want k )
        : f d ( fabs - ( __s_get got + off k ) w )
        ? > d md { = md d } {}
        ? > ( fabs w ) mx { = mx ( fabs w ) } {}
        = k + k 1
    }
    : f rel / md mx
    ? < rel 1.0e-4 { ( nurl_print `  ok   ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    : String msg ( string_from label )
    ( string_push_str msg `  max |Δ| ` )
    ( string_push_float msg md )
    ( string_push_str msg `  relative ` )
    ( string_push_float msg rel )
    ( nurl_println ( string_data msg ) )
    ( string_free msg )
}

@ main → i {
    : s ckpt ( nurl_argv_get 1 )
    : s vocab ( nurl_argv_get 2 )
    : s dir ( nurl_argv_get 3 )
    : ( Vec i ) ids ( __s_read_i32 dir `text_ids.i32` )
    : ( Vec f ) noise ( __s_read_f32 dir `noise.f32` )
    : ( Vec f ) cond ( __s_read_f32 dir `cond_mel.f32` )
    : ( Vec f ) wpred ( __s_read_f32 dir `s0_pred.f32` )
    : ( Vec f ) wnull ( __s_read_f32 dir `s0_null.f32` )
    : i n / ( vec_len [f] noise ) 100
    ?? ( f5_open ckpt vocab -1 ) {
        T m → {
            ? ( f5_alloc m n 2 ) {} { ( nurl_eprintln `alloc failed` ) ^ 1 }
            ? ( f5_rope m ) {} { ( nurl_eprintln `rope failed` ) ^ 1 }
            ? ( f5_text_encode m ids F 0 ) {} { ( nurl_eprintln `text cond failed` ) ^ 1 }
            ? ( f5_text_encode m ids T n ) {} { ( nurl_eprintln `text uncond failed` ) ^ 1 }
            : ( Vec f ) wtc ( __s_read_f32 dir `text_cond.f32` )
            : ( Vec f ) wtu ( __s_read_f32 dir `text_uncond.f32` )
            : ( Vec f ) gtxt ( vec_new [f] )
            ? ( f5_download m ( f5_buf_txt m ) gtxt * 2 * n 512 ) {} {}
            ( __s_cmp gtxt 0 wtc `the conditional text encoder` )
            ( __s_cmp gtxt * n 512 wtu `the unconditional text encoder` )
            ( vec_free [f] gtxt ) ( vec_free [f] wtc ) ( vec_free [f] wtu )
            : ( Vec f ) c2 ( vec_with_cap [f] * 2 * n 100 )
            : i have ( vec_len [f] cond )
            : ~ i k 0
            ~ < k * n 100 { ( vec_push [f] c2 ? < k have ( __s_get cond k ) 0.0 ) = k + k 1 }
            = k 0
            ~ < k * n 100 { ( vec_push [f] c2 0.0 ) = k + k 1 }
            ? ( gk_dbuf_upload ( f5_kit m ) ( f5_buf_cond m ) c2 ) {} { ( nurl_eprintln `cond upload` ) ^ 1 }
            ? ( f5_set_x m noise ) {} { ( nurl_eprintln `x upload` ) ^ 1 }
            ? ( f5_set_one_time m 0.0 ) {} { ( nurl_eprintln `time` ) ^ 1 }
            ? ( f5_forward m ) {} { ( nurl_eprintln `forward` ) ^ 1 }
            : ( Vec f ) got ( vec_new [f] )
            ? ( f5_download m ( f5_buf_pred m ) got * 2 * n 100 ) {} { ( nurl_eprintln `download` ) ^ 1 }
            ( __s_cmp got 0 wpred `the conditional half` )
            ( __s_cmp got * n 100 wnull `the unconditional half` )
            ( vec_free [f] got )
            ( vec_free [f] c2 )
            ( f5_close m )
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
    }
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}
