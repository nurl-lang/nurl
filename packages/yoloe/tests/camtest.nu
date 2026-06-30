// camtest.nu — smoke-test the pure-NURL V4L2 webcam capture: open the camera,
// grab a few frames (discarding the first, which is often dark while the
// sensor warms up), and write the last as a PPM.
//   camtest <device> <w> <h> <out.ppm>

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `../src/image.nu`
$ `../src/v4l2.nu`

@ p s m → v { ( nurl_print m ) }
@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 5 { ( p `usage: camtest <device> <w> <h> <out.ppm>\n` ) ^ 2 } {}
    : String dev ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : i w ( nurl_str_to_int ?? ( vec_get [String] av 2 ) { T x → ( string_data x ) F _ → `640` } )
    : i h ( nurl_str_to_int ?? ( vec_get [String] av 3 ) { T x → ( string_data x ) F _ → `480` } )
    : String outp ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }

    : Camera c ( cam_open ( string_data dev ) w h 4 )
    ? ! ( cam_ok c ) { ( p `cannot open camera ` ) ( p ( string_data dev ) ) ( p `\n` ) ^ 1 } {}
    ( p `camera ` ) ( pn ( cam_w c ) ) ( p `x` ) ( pn ( cam_h c ) ) ( p ` streaming\n` )

    : i aw ( cam_w c )
    : i ah ( cam_h c )
    : ( Vec u ) rgb ( vec_new [u] )
    : ~ i z 0
    ~ < z * * aw ah 3 { ( vec_push [u] rgb 0 ) = z + z 1 }

    : ~ i ok 0
    : ~ i f 0
    ~ < f 6 {
        ? ( cam_grab c rgb ) { = ok + ok 1 } {}
        = f + f 1
    }
    ( p `grabbed ` ) ( pn ok ) ( p ` frames\n` )
    ( cam_close c )

    : Image im @ Image { aw ah rgb 0 }
    ? ( ppm_write ( string_data outp ) im ) { ( p `wrote ` ) ( p ( string_data outp ) ) ( p `\n` ) ^ 0 } { ( p `write failed\n` ) ^ 1 }
}
