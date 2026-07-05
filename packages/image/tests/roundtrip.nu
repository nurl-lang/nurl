// tests/roundtrip.nu — load an image, re-encode it as PNG and PPM.
//   roundtrip <in> <out.png> <out.ppm>
// The harness (image_test.sh) checks the outputs against Pillow.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `src/image.nu`

@ main → i {
    ? >= ( env_args_count ) 4 {} {
        ( nurl_eprintln `usage: roundtrip <in> <out.png> <out.ppm>` )
        ^ 2
    }
    : String a1 ( env_arg 1 )
    : String a2 ( env_arg 2 )
    : String a3 ( env_arg 3 )
    : ~ i rc 0
    ?? ( image_load ( string_data a1 ) ) {
        T im → {
            : String meta ( string_from `decoded ` )
            ( string_push_int meta ( image_width im ) )
            ( string_push_char meta 120 )
            ( string_push_int meta ( image_height im ) )
            ( string_push_str meta ` ch=` )
            ( string_push_int meta ( image_channels im ) )
            ( nurl_eprintln ( string_data meta ) )
            ( string_free meta )
            ? ( image_save_png ( string_data a2 ) im ) {} { ( nurl_eprintln `png save failed` ) = rc 1 }
            ? ( image_save_ppm ( string_data a3 ) im ) {} { ( nurl_eprintln `ppm save failed` ) = rc 1 }
            ( image_free im )
        }
        F _ → { ( nurl_eprintln `decode failed` ) = rc 1 }
    }
    ( string_free a1 )
    ( string_free a2 )
    ( string_free a3 )
    ^ rc
}
