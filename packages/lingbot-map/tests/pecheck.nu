// pecheck.nu — patch-embed a deterministic image with deterministic
// weights and print every output value, in the format
// tests/pe_oracle.py emits from torch's Conv2d(3, n, k, stride=k).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/patchembed.nu`

@ case i c i h i w i patch i nout → v {
    : i p ( pe_patches h w patch )
    : i k * c * patch patch
    : ( Vec f ) img__v ( vec_zeroed [f] * c * h w )
    : ( Slice f ) img ( slice_from_vec [f] img__v )
    : ( Vec f ) wgt__v ( vec_zeroed [f] * nout k )
    : ( Slice f ) wgt ( slice_from_vec [f] wgt__v )
    : ( Vec f ) bia__v ( vec_zeroed [f] nout )
    : ( Slice f ) bia ( slice_from_vec [f] bia__v )
    : ( Vec f ) col__v ( vec_zeroed [f] * p k )
    : ( Slice f ) col ( slice_from_vec [f] col__v )
    : ( Vec f ) out__v ( vec_zeroed [f] * p nout )
    : ( Slice f ) out ( slice_from_vec [f] out__v )
    : ~ i j 0
    ~ < j * c * h w { ( slice_put [f] img j ( float_sin + 0.3 * 0.017 # f j ) ) = j + j 1 }
    = j 0
    ~ < j * nout k { ( slice_put [f] wgt j ( float_cos + 0.7 * 0.011 # f j ) ) = j + j 1 }
    = j 0
    ~ < j nout { ( slice_put [f] bia j * 0.01 # f - j 2 ) = j + j 1 }
    ( pe_im2col img c h w patch col )
    ( pe_project col p k wgt bia nout out )
    ( nurl_print `p` ) ( nurl_print ( nurl_str_int c ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int patch ) )
    ( nurl_print `_` ) ( nurl_print ( nurl_str_int nout ) )
    = j 0
    ~ < j * p nout { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float ( slice_at [f] out j ) ) ) = j + j 1 }
    ( nurl_print `\n` )
}

@ main → i {
    ( case 3 28 42 14 5 )  // 2x3 patches, the real patch size
    ( case 3 14 14 14 4 )  // a single patch
    ( case 2 12 8 4 6 )  // 3x2 patches, small kernel
    ^ 0
}
