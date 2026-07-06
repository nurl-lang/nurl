// tests/devcheck.nu — device-resident buffer + kernel battery. Prints
//   name|v0,v1,…   (or SKIP when no device/backend)
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/dev.nu`

@ pv s name ( Vec f ) v → v {
    : String o ( string_from name )
    ( string_push_char o 124 )
    : i n ( vec_len [f] v )
    : ~ i k 0
    ~ < k n {
        ? > k 0 { ( string_push_char o 44 ) } {}
        ?? ( vec_get [f] v k ) { T x → { ( string_push_float o x ) } F _ → {} }
        = k + k 1
    }
    ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
    ( string_free o )
}

@ fill i n f base f step → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v + base * step # f k ) = k + k 1 }
    ^ v
}

@ zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

@ run_dtype * GpuKit kit i dt s tag → v {
    // a = [0..11], b = [1..12] as 3x4; scalar s = 0.5
    : ( Vec f ) ha ( fill 12 0.0 1.0 )
    : ( Vec f ) hb ( fill 12 1.0 1.0 )
    : GkBuf a ( gk_dbuf_new kit 12 dt )
    : GkBuf b ( gk_dbuf_new kit 12 dt )
    : GkBuf o ( gk_dbuf_new kit 12 dt )
    : GkBuf sc ( gk_dbuf_new kit 1 dt )
    ( gk_dbuf_upload kit a ha )
    ( gk_dbuf_upload kit b hb )
    : ( Vec f ) hs ( fill 1 0.5 0.0 )
    ( gk_dbuf_upload kit sc hs )
    : ( Vec f ) out ( zeros 12 )

    ( gkd_add kit o a b )
    ( gk_dbuf_download kit o out )
    : String n1 ( string_from tag ) ( string_push_str n1 `_add` )
    ( pv ( string_data n1 ) out ) ( string_free n1 )

    ( gkd_mul kit o a sc )  // scalar broadcast
    ( gk_dbuf_download kit o out )
    : String n2 ( string_from tag ) ( string_push_str n2 `_muls` )
    ( pv ( string_data n2 ) out ) ( string_free n2 )

    ( gkd_sigmoid kit o a )
    ( gk_dbuf_download kit o out )
    : String n3 ( string_from tag ) ( string_push_str n3 `_sig` )
    ( pv ( string_data n3 ) out ) ( string_free n3 )

    // chained on device: relu(a·bT-ish) — use a as 3x4, b as 4x3 (reuse hb)
    : GkBuf mm ( gk_dbuf_new kit 9 dt )
    ( gkd_matmul kit mm a b 3 4 3 )
    : ( Vec f ) mout ( zeros 9 )
    ( gk_dbuf_download kit mm mout )
    : String n4 ( string_from tag ) ( string_push_str n4 `_mm` )
    ( pv ( string_data n4 ) mout ) ( string_free n4 )

    // softmax rows over the matmul result (3x3), still on device
    : GkBuf sm ( gk_dbuf_new kit 9 dt )
    ( gkd_softmax_rows kit sm mm 3 3 )
    ( gk_dbuf_download kit sm mout )
    : String n5 ( string_from tag ) ( string_push_str n5 `_smax` )
    ( pv ( string_data n5 ) mout ) ( string_free n5 )

    ?? ( gkd_sum kit a ) {
        T s → {
            : String n6 ( string_from tag ) ( string_push_str n6 `_sum` )
            : ( Vec f ) sv ( fill 1 s 0.0 )
            ( pv ( string_data n6 ) sv ) ( string_free n6 ) ( vec_free [f] sv )
        }
        F _ → { ( nurl_print `sum FAIL\n` ) }
    }

    ( gk_dbuf_free a ) ( gk_dbuf_free b ) ( gk_dbuf_free o )
    ( gk_dbuf_free sc ) ( gk_dbuf_free mm ) ( gk_dbuf_free sm )
    ( vec_free [f] ha ) ( vec_free [f] hb ) ( vec_free [f] hs )
    ( vec_free [f] out ) ( vec_free [f] mout )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ( gk_close kit ) ^ 0 }
    ( nurl_print `backend|` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( run_dtype kit GK_F32 `f32` )
    ( run_dtype kit GK_F64 `f64` )
    ( gk_close kit )
    ^ 0
}
