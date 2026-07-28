// tests/interpcheck.nu — interp_bicubic_torch against torch's own
// upsample_bicubic2d. tests/interp_oracle.py prints the same grids out
// of F.interpolate(mode="bicubic", antialias=False, scale_factor=...)
// with DINOv2's +0.1 offset; the test is a numeric diff (the oracle
// runs f32, this runs f64, so the gate is 1e-5 absolute, not bytes).
//
// The input is a deterministic pseudo-random field — smooth inputs
// forgive a wrong tap offset; this does not.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/interp.nu`

: i IC_M 37
: i IC_C 3

@ __ic_val i k i p → f {
    : i v % + + * 37 p * 91 k * 13 % * p k 7 251
    ^ / # f v 251.0
}

@ __ic_case i oh i ow → v {
    : i ihw * IC_M IC_M
    : *f pin # *f ( nurl_zalloc * 8 * IC_C ihw )
    : ~ i k 0
    ~ < k IC_C {
        : ~ i p 0
        ~ < p ihw { = . pin + * k ihw p ( __ic_val k p ) = p + p 1 }
        = k + k 1
    }
    : *f pout # *f ( nurl_zalloc * 8 * IC_C * oh ow )
    // DINOv2's kludge: scale_factor = (out + 0.1)/37, torch then uses
    // its reciprocal for the coordinate map.
    : f rsy / # f IC_M + # f oh 0.1
    : f rsx / # f IC_M + # f ow 0.1
    ( interp_bicubic_torch pin IC_M IC_M IC_C oh ow rsy rsx pout )
    : String line ( string_from `case ` )
    ( string_push_int line oh )
    ( string_push_char line 32 )
    ( string_push_int line ow )
    : ~ i j 0
    ~ < j * IC_C * oh ow {
        ( string_push_char line 32 )
        ( string_push_float line . pout j )
        = j + j 1
    }
    ( puts ( string_data line ) )
    ( string_free line )
    ( nurl_free # s pin )
    ( nurl_free # s pout )
}

@ main → i {
    ( __ic_case 28 37 )  // 518x392 landscape: rows shrink
    ( __ic_case 37 28 )  // portrait
    ( __ic_case 21 37 )  // 518x294
    ( __ic_case 12 37 )  // 518x168, the extreme aspect
    ( __ic_case 40 40 )  // upsample both axes
    ^ 0
}
