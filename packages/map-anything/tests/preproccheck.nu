// tests/preproccheck.nu — pp_* against the reference preprocessing.
//
// tests/preproc_oracle.py writes synthetic PNGs into a directory and
// prints the shared target size plus every resized-cropped byte out of
// the reference's own crop_resize_if_necessary. This program reads the
// same PNGs and prints the same dump out of pp_open / pp_pick_target /
// pp_fit; the test is a byte diff. pp_fit hands back [0,1] floats that
// are exactly n/255, so round(v·255) recovers the bytes losslessly.
//
//   preproccheck <dir-with-pp_N.png>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/image.nu`
$ `src/preproc.nu`

: i __PC_N 5

@ main → i {
    ? < ( nurl_argc ) 2 {
        ( puts `usage: preproccheck <dir>` )
        ^ 2
    } {}
    : s dir ( nurl_argv 1 )

    // Pass 1: open everything, average the aspect ratios.
    : ( Vec Image ) imgs ( vec_new [Image] )
    : ~ f aspect_sum 0.0
    : ~ i k 0
    ~ < k __PC_N {
        : String p ( string_from dir )
        ( string_push_str p `/pp_` )
        ( string_push_int p k )
        ( string_push_str p `.png` )
        ?? ( pp_open ( string_data p ) ) {
            F e → {
                ( puts ( string_data e ) )
                ( string_free e )
                ( string_free p )
                ^ 1
            }
            T im → {
                = aspect_sum + aspect_sum / # f . im width # f . im height
                ( vec_push [Image] imgs im )
            }
        }
        ( string_free p )
        = k + k 1
    }
    : i target ( pp_pick_target / aspect_sum # f __PC_N )
    : i tw ( pp_target_w target )
    : i th ( pp_target_h target )
    : String head ( string_from `target ` )
    ( string_push_int head tw )
    ( string_push_char head 32 )
    ( string_push_int head th )
    ( puts ( string_data head ) )
    ( string_free head )

    // Pass 2: fit each image and dump HWC bytes, oracle order.
    = k 0
    ~ < k __PC_N {
        ?? ( vec_get [Image] imgs k ) {
            F → {}
            T im → {
                ?? ( pp_fit im tw th ) {
                    F e → {
                        ( puts ( string_data e ) )
                        ( string_free e )
                        ^ 1
                    }
                    T fr → {
                        : String line ( string_from `img` )
                        ( string_push_int line k )
                        ( string_push_char line 32 )
                        ( string_push_int line tw )
                        ( string_push_str line `x` )
                        ( string_push_int line th )
                        : *f dp ( pp_data fr )
                        : i plane * tw th
                        : ~ i y 0
                        ~ < y th {
                            : ~ i x 0
                            ~ < x tw {
                                : ~ i c 0
                                ~ < c 3 {
                                    : i v # i + * . dp + * c plane + * y tw x 255.0 0.5
                                    ( string_push_char line 32 )
                                    ( string_push_int line v )
                                    = c + c 1
                                }
                                = x + x 1
                            }
                            = y + y 1
                        }
                        ( puts ( string_data line ) )
                        ( string_free line )
                        ( pp_free fr )
                    }
                }
            }
        }
        = k + k 1
    }
    ( vec_free_with [Image] imgs \ Image im → v { ( image_free im ) } )
    ^ 0
}
