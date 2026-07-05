// wintest.nu — open an X11 window and show a PPM, to verify window.nu.
//   wintest <image.ppm> [iters]

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `../src/image.nu`
$ `../src/window.nu`

& `c` @ usleep i usec → i

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 2 { ( nurl_print `usage: wintest <image.ppm> [iters]\n` ) ^ 2 } {}
    : String ip ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : i iters ? > ( vec_len [String] av ) 2 ( nurl_str_to_int ?? ( vec_get [String] av 2 ) { T x → ( string_data x ) F _ → `60` } ) 60
    ?? ( img_load ( string_data ip ) ) {
        T im → {
            : i w ( img_w im )
            : i h ( img_h im )
            ( nurl_print `image ` ) ( nurl_print ( nurl_str_int w ) ) ( nurl_print `x` ) ( nurl_print ( nurl_str_int h ) ) ( nurl_print `\n` )
            : XWin win ( xwin_open w h `yoloe wintest` )
            ? ! ( xwin_ok win ) { ( nurl_print `no X display (DISPLAY unset?)\n` ) ^ 1 } {}
            ( nurl_print `window open; showing for a moment...\n` )
            : ~ i k 0
            ~ < k iters {
                ( xwin_show win im )
                ( usleep 50000 )
                ? ( xwin_should_close win ) { = k iters } { = k + k 1 }
            }
            ( xwin_close win )
            ( nurl_print `closed\n` )
            ^ 0
        }
        F _ → { ( nurl_print `cannot read PPM\n` ) ^ 1 }
    }
}
