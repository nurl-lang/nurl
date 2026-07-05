// img — the image package's command-line tool.
//
//   img info <file>                     format-sniffed decode + geometry
//   img convert <in> <out> [-q N]       transcode; format from <out>'s
//                                       extension (.png .jpg .jpeg .ppm .pgm)
//   img resize <in> <out> <W>x<H> [-q N]
//                                       resize + transcode. `800x600` exact,
//                                       `800x` / `x600` keep aspect. Shrinks
//                                       use box averaging (clean thumbnails),
//                                       growth uses bilinear.
//
//   -q N    JPEG quality 1–100 (default 90)
//
// Exit codes: 0 ok · 1 processing error · 2 usage.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/args.nu`
$ `stdlib/ext/env.nu`
$ `image.nu`

// Output format from a path's extension: 1 png, 2 jpeg, 3 ppm, 4 pgm, 0 unknown.
@ __img_fmt_of String path → i {
    : String low ( string_to_lower path )
    : ~ i f 0
    ? ( string_ends_with low `.png` ) { = f 1 } {}
    ? || ( string_ends_with low `.jpg` ) ( string_ends_with low `.jpeg` ) { = f 2 } {}
    ? ( string_ends_with low `.ppm` ) { = f 3 } {}
    ? ( string_ends_with low `.pgm` ) { = f 4 } {}
    ( string_free low )
    ^ f
}

// Save by format id; pgm converts to greyscale first.
@ __img_save i fmt s path Image im i quality → b {
    ? == fmt 1 { ^ ( image_save_png path im ) } {}
    ? == fmt 2 { ^ ( image_save_jpeg path im quality ) } {}
    ? == fmt 3 { ^ ( image_save_ppm path im ) } {}
    ? == fmt 4 {
        : Image g ( image_convert im 1 )
        : b ok ( image_save_ppm path g )
        ( image_free g )
        ^ ok
    } {}
    ^ F
}

// Parse `WxH` / `Wx` / `xH`; scaled dims land in wh[0], wh[1] (0 = derive).
@ __img_parse_wh String spec *u wh → b {
    : i n ( string_len spec )
    : ~ i w 0
    : ~ i h 0
    : ~ i xpos -1
    : ~ i k 0
    ~ < k n {
        : i c ( string_get spec k )
        ? || == c 120 == c 88 { = xpos k } {}     // 'x' / 'X'
        = k + k 1
    }
    ? < xpos 0 { ^ F } {}
    : ~ i k2 0
    ~ < k2 xpos {
        : i c ( string_get spec k2 )
        ? & >= c 48 <= c 57 { = w + * w 10 - c 48 } { ^ F }
        = k2 + k2 1
    }
    = k2 + xpos 1
    ~ < k2 n {
        : i c ( string_get spec k2 )
        ? & >= c 48 <= c 57 { = h + * h 10 - c 48 } { ^ F }
        = k2 + k2 1
    }
    ? & == w 0 == h 0 { ^ F } {}
    ( nurl_poke wh 0 w )
    ( nurl_poke wh 1 h )
    ^ T
}

@ __img_info s path → i {
    ?? ( image_load path ) {
        T im → {
            : String m ( string_from path )
            ( string_push_str m `: ` )
            ( string_push_int m ( image_width im ) )
            ( string_push_char m 120 )
            ( string_push_int m ( image_height im ) )
            ( string_push_str m ` ` )
            : i ch ( image_channels im )
            ? == ch 1 { ( string_push_str m `greyscale` ) } {
            ? == ch 2 { ( string_push_str m `greyscale+alpha` ) } {
            ? == ch 3 { ( string_push_str m `RGB` ) } {
                ( string_push_str m `RGBA` )
            } } }
            ( puts ( string_data m ) )
            ( string_free m )
            ( image_free im )
            ^ 0
        }
        F _ → {
            ( nurl_eprintln `img: cannot decode (unsupported or corrupt file)` )
            ^ 1
        }
    }
}

@ main → i {
    : ArgParser p ( args_new `img` `decode, convert and resize images (PNG / JPEG / PPM)` )
    ( args_opt p `quality` 113 `N` `JPEG quality 1-100 (default 90)` )
    ( args_flag p `help` 104 `show usage` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    : i npos ( args_positional_count p )
    ? || ( args_present p `help` ) < npos 1 {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  img info <file>\n  img convert <in> <out> [-q N]\n  img resize <in> <out> <W>x<H> [-q N]   (800x600, 800x, x600)\n` )
        ( string_free u )
        : b washelp ( args_present p `help` )
        ( args_free p )
        ^ ? washelp { 0 } { 2 }
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ i rc 0

    : ~ s cmds ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmds ( string_data c ) } F _ → {} }

    ? ( nurl_str_eq cmds `info` ) {
        ? >= npos 2 {
            ?? ( vec_get [String] pos 1 ) {
                T f → { = rc ( __img_info ( string_data f ) ) }
                F _ → { = rc 2 }
            }
        } { ( nurl_eprintln `usage: img info <file>` ) = rc 2 }
        ( args_free p )
        ^ rc
    } {}

    : b is_conv ( nurl_str_eq cmds `convert` )
    : b is_rsz ( nurl_str_eq cmds `resize` )
    ? || is_conv is_rsz {} {
        ( nurl_eprintln `img: unknown command (info / convert / resize)` )
        ( args_free p )
        ^ 2
    }
    : i want ? is_conv { 3 } { 4 }
    ? >= npos want {} {
        ( nurl_eprintln ? is_conv { `usage: img convert <in> <out> [-q N]` } { `usage: img resize <in> <out> <W>x<H> [-q N]` } )
        ( args_free p )
        ^ 2
    }

    : ~ s inpath ``
    : ~ s outpath ``
    ?? ( vec_get [String] pos 1 ) { T v → { = inpath ( string_data v ) } F _ → {} }
    ?? ( vec_get [String] pos 2 ) { T v → { = outpath ( string_data v ) } F _ → {} }

    // quality
    : String qs ( args_value_or p `quality` `90` )
    : ~ i quality 0
    : ~ i qk 0
    : i qn ( string_len qs )
    ~ < qk qn {
        : i c ( string_get qs qk )
        ? & >= c 48 <= c 57 { = quality + * quality 10 - c 48 } {}
        = qk + qk 1
    }
    ( string_free qs )
    ? || < quality 1 > quality 100 { = quality 90 } {}

    : ~ i outfmt 0
    ?? ( vec_get [String] pos 2 ) { T v → { = outfmt ( __img_fmt_of v ) } F _ → {} }
    ? > outfmt 0 {} {
        ( nurl_eprintln `img: cannot tell the output format — use .png / .jpg / .ppm / .pgm` )
        ( args_free p )
        ^ 2
    }

    ?? ( image_load inpath ) {
        T im → {
            : ~ b saved F
            : ~ b size_err F
            ? is_conv {
                = saved ( __img_save outfmt outpath im quality )
            } {
                : *u wh ( nurl_alloc 16 )
                : ~ b whok F
                ?? ( vec_get [String] pos 3 ) {
                    T spec → { = whok ( __img_parse_wh spec wh ) }
                    F _ → {}
                }
                ? whok {
                    : ~ i nw ( nurl_peek wh 0 )
                    : ~ i nh ( nurl_peek wh 1 )
                    : i ow ( image_width im )
                    : i oh ( image_height im )
                    // derive the missing dimension, keeping aspect
                    ? == nw 0 { = nw / + * ow nh / oh 2 oh } {}
                    ? == nh 0 { = nh / + * oh nw / ow 2 ow } {}
                    ? < nw 1 { = nw 1 } {}
                    ? < nh 1 { = nh 1 } {}
                    // box-average when shrinking, bilinear when growing
                    : Image rs ? & <= nw ow <= nh oh { ( image_resize_area im nw nh ) } { ( image_resize im nw nh ) }
                    = saved ( __img_save outfmt outpath rs quality )
                    ( image_free rs )
                } {
                    ( nurl_eprintln `img: bad size — use 800x600, 800x or x600` )
                    = size_err T
                }
                ( nurl_free # s wh )
            }
            ( image_free im )
            ? size_err { = rc 2 } {
                ? saved {} {
                    ( nurl_eprintln `img: could not process/write output` )
                    = rc 1
                }
            }
        }
        F _ → {
            ( nurl_eprintln `img: cannot decode input (unsupported or corrupt file)` )
            = rc 1
        }
    }
    ( args_free p )
    ^ rc
}
