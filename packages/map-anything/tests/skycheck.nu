// tests/skycheck.nu — the sky mask against the reference's.
//
// Preprocesses <image> with pp_* (byte-identical to the reference's
// load_images), runs sky_mask over an all-ones mask, and writes the
// keep-mask as u8. tests/sky_oracle.py writes the reference's; the
// comparison is a pixel-agreement count (the resamplers differ at
// cv2-vs-port rounding level, so the gate is agreement ≥ 99%, not
// byte equality).
//
//   skycheck <image> <skyseg.onnx> <out_mask.bin> <tw> <th>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/ops.nu`
$ `deps/image/src/image.nu`
$ `src/preproc.nu`
$ `src/sky.nu`

@ __sc_die s msg → i {
    ( puts msg )
    ^ 1
}

@ main → i {
    ? < ( nurl_argc ) 6 { ^ ( __sc_die `usage: skycheck <image> <skyseg.onnx> <out.bin> <tw> <th>` ) } {}
    : s img ( nurl_argv 1 )
    : s model ( nurl_argv 2 )
    : s outp ( nurl_argv 3 )
    : i tw ( nurl_str_to_int ( nurl_argv 4 ) )
    : i th ( nurl_str_to_int ( nurl_argv 5 ) )

    : ~ * Frame fr # *Frame 0
    ?? ( pp_open img ) {
        F e → {
            ( puts ( string_data e ) )
            ^ 1
        }
        T im → {
            ?? ( pp_fit im tw th ) {
                F e → {
                    ( puts ( string_data e ) )
                    ^ 1
                }
                T got → { = fr got }
            }
            ( image_free im )
        }
    }
    : Sky sky ( sky_open model )
    ? . sky ok {} { ^ ( __sc_die `cannot load skyseg.onnx` ) }
    : i hw * tw th
    : *u mask # *u ( nurl_zalloc hw )
    : ~ i j 0
    ~ < j hw { = . mask j # u 1 = j + j 1 }
    ? ( sky_mask sky ( pp_data fr ) tw th mask ) {} { ^ ( __sc_die `sky_mask failed` ) }
    : ( Vec u ) out ( vec_with_cap [u] hw )
    : ~ i kept 0
    = j 0
    ~ < j hw {
        ( vec_push [u] out . mask j )
        ? != # i . mask j 0 { = kept + kept 1 } {}
        = j + j 1
    }
    ?? ( write_file_bytes outp out ) {
        T → {}
        F → { ^ ( __sc_die `cannot write mask` ) }
    }
    : String m ( string_from `kept ` )
    ( string_push_int m kept )
    ( string_push_str m ` / ` )
    ( string_push_int m hw )
    ( puts ( string_data m ) )
    ^ 0
}
