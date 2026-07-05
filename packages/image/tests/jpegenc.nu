// tests/jpegenc.nu — encode a source image as JPEG four ways and prove the
// encoder round-trips through our OWN decoder.
//   jpegenc <in.png> <out444.jpg> <out420.jpg> <out422.jpg> <outgray.jpg> [loose]
// Prints "self <name> max=<d>" per variant (max abs channel diff of
// decode(encode(im)) vs im). The harness then re-decodes the files with
// Pillow and checks them against the source. With `loose`, self-decode
// tolerances are disabled (noise + chroma subsampling is legitimately far
// from the source — Pillow's own encoder measures the same) and only
// encode/decode structural health is checked.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `src/image.nu`

: ~ i g_fail 0

// Max abs diff over the shared channel count.
@ maxdiff Image a Image b → i {
    ? || != ( image_width a ) ( image_width b ) != ( image_height a ) ( image_height b ) { ^ 999 } {}
    : i ch ? < ( image_channels a ) ( image_channels b ) { ( image_channels a ) } { ( image_channels b ) }
    : ~ i worst 0
    : ~ i y 0
    ~ < y ( image_height a ) {
        : ~ i x 0
        ~ < x ( image_width a ) {
            : ~ i c 0
            ~ < c ch {
                : i d - ( image_get a x y c ) ( image_get b x y c )
                : i ad ? < d 0 { - 0 d } { d }
                ? > ad worst { = worst ad } {}
                = c + c 1
            }
            = x + x 1
        }
        = y + y 1
    }
    ^ worst
}

@ enc_one Image src s outpath i quality i subsamp s name i tol → v {
    : ( Vec u ) enc ( jpeg_encode_sub src quality subsamp )
    ?? ( write_file_bytes outpath enc ) { T _ → {} F _ → { ( nurl_eprintln `write failed` ) = g_fail 1 } }
    ?? ( jpeg_decode enc ) {
        T dec → {
            : i d ( maxdiff src dec )
            : String m ( string_from `self ` )
            ( string_push_str m name )
            ( string_push_str m ` max=` )
            ( string_push_int m d )
            ( puts ( string_data m ) )
            ( string_free m )
            ? <= d tol {} { ( nurl_eprintln `FAIL self-decode diff over tolerance` ) = g_fail 1 }
            ( image_free dec )
        }
        F _ → { ( nurl_eprintln `FAIL own decoder rejected our encode` ) = g_fail 1 }
    }
    ( vec_free [u] enc )
}

@ main → i {
    ? >= ( env_args_count ) 6 {} {
        ( nurl_eprintln `usage: jpegenc <in.png> <out444> <out420> <out422> <outgray>` )
        ^ 2
    }
    : String a1 ( env_arg 1 )
    : String a2 ( env_arg 2 )
    : String a3 ( env_arg 3 )
    : String a4 ( env_arg 4 )
    : String a5 ( env_arg 5 )
    : ~ i tol1 24
    : ~ i tol2 48
    ? >= ( env_args_count ) 7 { = tol1 255 = tol2 255 } {}
    ?? ( image_load ( string_data a1 ) ) {
        T im → {
            ( enc_one im ( string_data a2 ) 95 0 `444 q95` tol1 )
            ( enc_one im ( string_data a3 ) 90 2 `420 q90` tol2 )
            ( enc_one im ( string_data a4 ) 90 1 `422 q90` tol2 )
            : Image grey ( image_convert im 1 )
            ( enc_one grey ( string_data a5 ) 95 0 `gray q95` tol1 )
            ( image_free grey )
            ( image_free im )
        }
        F _ → { ( nurl_eprintln `load failed` ) = g_fail 1 }
    }
    ( string_free a1 ) ( string_free a2 ) ( string_free a3 )
    ( string_free a4 ) ( string_free a5 )
    ^ g_fail
}
