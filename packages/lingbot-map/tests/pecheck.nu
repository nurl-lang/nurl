// pecheck.nu — patch-embed a deterministic image with deterministic
// weights and print every output value, in the format
// tests/pe_oracle.py emits from torch's Conv2d(3, n, k, stride=k).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/patchembed.nu`

unsafe @ case i c i h i w i patch i nout → v {
    : i p ( pe_patches h w patch )
    : i k * c * patch patch
    : ( Vec u ) img__v ( vec_zeroed [u] * 8 * c * h w )
    : *f img # *f ( vec_data [u] img__v )
    : ( Vec u ) wgt__v ( vec_zeroed [u] * 8 * nout k )
    : *f wgt # *f ( vec_data [u] wgt__v )
    : ( Vec u ) bia__v ( vec_zeroed [u] * 8 nout )
    : *f bia # *f ( vec_data [u] bia__v )
    : ( Vec u ) col__v ( vec_zeroed [u] * 8 * p k )
    : *f col # *f ( vec_data [u] col__v )
    : ( Vec u ) out__v ( vec_zeroed [u] * 8 * p nout )
    : *f out # *f ( vec_data [u] out__v )
    : ~ i j 0
    ~ < j * c * h w { = . img j ( float_sin + 0.3 * 0.017 # f j ) = j + j 1 }
    = j 0
    ~ < j * nout k { = . wgt j ( float_cos + 0.7 * 0.011 # f j ) = j + j 1 }
    = j 0
    ~ < j nout { = . bia j * 0.01 # f - j 2 = j + j 1 }
    ( pe_im2col img c h w patch col )
    ( pe_project col p k wgt bia nout out )
    ( nurl_print `p` ) ( nurl_print ( nurl_str_int c ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int patch ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int nout ) )
    = j 0
    ~ < j * p nout { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . out j ) ) = j + j 1 }
    ( nurl_print `\n` )
}

@ main → i {
    ( case 3 28 42 14 5 )  // 2x3 patches, the real patch size
    ( case 3 14 14 14 4 )  // a single patch
    ( case 2 12 8 4 6 )  // 3x2 patches, small kernel
    ^ 0
}
