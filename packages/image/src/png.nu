// image/png.nu — PNG decode + encode over the stdlib DEFLATE codec.
//
// Decode: the full still-image feature matrix — every legal bit depth
// (1 / 2 / 4 / 8 / 16, deeper samples scaled to the 8-bit raster), every
// colour type (grey, RGB, palette → RGB, grey+alpha, RGBA), Adam7
// interlacing, and tRNS transparency (palette alpha and grey/RGB colour
// keys, which add an alpha channel to the output). All five scanline
// filters are reconstructed at any pixel width. Encode: 8-bit,
// non-interlaced, filter 0, colour type chosen from the image's channel
// count. Lossless — a decode→encode→decode round-trip reproduces the
// pixels exactly.
//
// `png_decode` returns None on malformed input; the codec never reads out
// of bounds.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/deflate.nu`
$ `core.nu`

@ __abs i x → i { ? < x 0 { ^ - 0 x } {} ^ x }

@ __paeth i a i b i c → i {
    : i p - + a b c
    : i pa ( __abs - p a )
    : i pb ( __abs - p b )
    : i pc ( __abs - p c )
    ? & <= pa pb <= pa pc { ^ a } {}
    ? <= pb pc { ^ b } {}
    ^ c
}

// Raw samples-per-pixel for a PNG colour type (palette = 1 index byte).
@ __png_raw_ch i color → i {
    ? == color 0 { ^ 1 } {}
    ? == color 2 { ^ 3 } {}
    ? == color 3 { ^ 1 } {}
    ? == color 4 { ^ 2 } {}
    ? == color 6 { ^ 4 } {}
    ^ 0
}

// ── Decode ────────────────────────────────────────────────────────────

// Is depth legal for this colour type?
@ __png_depth_ok i color i depth → b {
    : b sub8 ? || || == depth 1 == depth 2 == depth 4 { T } { F }
    ? == color 0 { ^ ? || || sub8 == depth 8 == depth 16 { T } { F } } {}
    ? == color 3 { ^ ? || sub8 == depth 8 { T } { F } } {}
    ? || || == color 2 == color 4 == color 6 { ^ ? || == depth 8 == depth 16 { T } { F } } {}
    ^ F
}

// Scale a raw sample at `depth` bits to 0..255.
@ __png_scale8 i s i depth → i {
    ? == depth 1 { ^ * s 255 } {}
    ? == depth 2 { ^ * s 85 } {}
    ? == depth 4 { ^ * s 17 } {}
    ? == depth 16 { ^ >> s 8 } {}
    ^ s
}

// Raw sample `si` (sample index within the row) from a reconstructed row.
@ __png_sample ( Vec u ) recon i rowbase i si i depth → i {
    ? == depth 8 { ^ ( __b recon + rowbase si ) } {}
    ? == depth 16 {
        : i o + rowbase * si 2
        ^ + * ( __b recon o ) 256 ( __b recon + o 1 )
    } {}
    : i bitpos * si depth
    : i byte ( __b recon + rowbase / bitpos 8 )
    : i shift - - 8 depth % bitpos 8
    ^ & >> byte shift - << 1 depth 1
}

// Decode one (sub-)image pass: unfilter `ph` rows of `pw` pixels starting
// at raw[offset], then scatter the pixels into `out` on the (x0,y0,dx,dy)
// lattice. Returns the number of raw bytes consumed, or -1 on error.
// trns: palette-alpha bytes (colour 3) or 16-bit colour-key samples
// (colour 0/2); tn = entry count.
@ __png_pass ( Vec u ) raw i offset i W i H i x0 i y0 i dx i dy i color i depth ( Vec u ) plte ( Vec i ) trns i tn ( Vec u ) out i outch → i {
    : i rch ( __png_raw_ch color )
    ? || <= W x0 <= H y0 { ^ 0 } {}
    : i pw / + - W x0 - dx 1 dx
    : i ph / + - H y0 - dy 1 dy
    ? || <= pw 0 <= ph 0 { ^ 0 } {}
    : i sbytes / + * * pw rch depth 7 8
    : i bpp / + * rch depth 7 8
    : i need * ph + sbytes 1
    ? > + offset need ( vec_len [u] raw ) { ^ -1 } {}

    // unfilter this pass's rows into a compact buffer
    : ( Vec u ) recon ( vec_with_cap [u] * ph sbytes )
    : ~ i y 0
    ~ < y ph {
        : i rowpos + offset * y + sbytes 1
        : i ft ( __b raw rowpos )
        ? > ft 4 { ( vec_free [u] recon ) ^ -1 } {}
        : i base + rowpos 1
        : ~ i x 0
        ~ < x sbytes {
            : i fv ( __b raw + base x )
            : i left ? >= x bpp { ( __b recon - + * y sbytes x bpp ) } { 0 }
            : i up ? > y 0 { ( __b recon - + * y sbytes x sbytes ) } { 0 }
            : i ul ? & > y 0 >= x bpp { ( __b recon - - + * y sbytes x bpp sbytes ) } { 0 }
            : ~ i rv 0
            ? == ft 0 { = rv fv } {}
            ? == ft 1 { = rv + fv left } {}
            ? == ft 2 { = rv + fv up } {}
            ? == ft 3 { = rv + fv / + left up 2 } {}
            ? == ft 4 { = rv + fv ( __paeth left up ul ) } {}
            ( vec_push [u] recon & rv 255 )
            = x + x 1
        }
        = y + y 1
    }

    // scatter pixels into the full-size output raster
    : i plen ( vec_len [u] plte )
    : ~ i j 0
    ~ < j ph {
        : i rowbase * j sbytes
        : i Y + y0 * j dy
        : ~ i i2 0
        ~ < i2 pw {
            : i X + x0 * i2 dx
            : i pos * + * Y W X outch
            ? == color 3 {
                : i idx ( __png_sample recon rowbase i2 depth )
                : i pi * idx 3
                ? < pi plen {
                    ( vec_set [u] out pos ( __b plte pi ) )
                    ( vec_set [u] out + pos 1 ( __b plte + pi 1 ) )
                    ( vec_set [u] out + pos 2 ( __b plte + pi 2 ) )
                } {}
                ? == outch 4 {
                    : i a ? < idx tn { ( __b_it trns idx ) } { 255 }
                    ( vec_set [u] out + pos 3 a )
                } {}
            } {
                // grey / RGB / grey+alpha / RGBA: emit scaled channels, then
                // a colour-key alpha when tRNS asks for one
                : ~ i c 0
                ~ < c rch {
                    : i s ( __png_sample recon rowbase + * i2 rch c depth )
                    ( vec_set [u] out + pos c ( __png_scale8 s depth ) )
                    = c + c 1
                }
                ? > outch rch {
                    : ~ b opaque F
                    : ~ i c2 0
                    ~ < c2 rch {
                        ? == ( __png_sample recon rowbase + * i2 rch c2 depth ) ( __b_it trns c2 ) {} { = opaque T }
                        = c2 + c2 1
                    }
                    ( vec_set [u] out + pos rch ? opaque { 255 } { 0 } )
                } {}
            }
            = i2 + i2 1
        }
        = j + j 1
    }
    ( vec_free [u] recon )
    ^ need
}

// int-vector read for tRNS (0 out of range)
@ __b_it ( Vec i ) v i p → i {
    ?? ( vec_get [i] v p ) { T x → { ^ x } F _ → { ^ 0 } }
}

@ png_decode ( Vec u ) buf → ?Image {
    : i n ( vec_len [u] buf )
    ? < n 8 { ^ @ ?Image { F } } {}
    // signature 137 80 78 71 13 10 26 10
    ? & == ( __b buf 0 ) 137 & == ( __b buf 1 ) 80 & == ( __b buf 2 ) 78 & == ( __b buf 3 ) 71 & == ( __b buf 4 ) 13 & == ( __b buf 5 ) 10 & == ( __b buf 6 ) 26 == ( __b buf 7 ) 10 {} {
        ^ @ ?Image { F }
    }

    : ~ i width 0
    : ~ i height 0
    : ~ i depth 0
    : ~ i color 0
    : ~ i interlace 0
    : ~ b have_ihdr F
    : ( Vec u ) zdata ( vec_new [u] )     // concatenated IDAT payloads
    : ( Vec u ) plte ( vec_new [u] )      // palette (RGB triples)
    : ( Vec u ) trnsb ( vec_new [u] )     // raw tRNS payload

    : ~ i p 8
    : ~ b going T
    ~ & going < + p 8 n {
        : i clen ( __u32be buf p )
        : i tpos + p 4
        : i t0 ( __b buf tpos )
        : i t1 ( __b buf + tpos 1 )
        : i t2 ( __b buf + tpos 2 )
        : i t3 ( __b buf + tpos 3 )
        : i dpos + p 8
        ? || < clen 0 > + dpos clen n { = going F } {
            // IHDR
            ? & == t0 73 & == t1 72 & == t2 68 == t3 82 {
                = width ( __u32be buf dpos )
                = height ( __u32be buf + dpos 4 )
                = depth ( __b buf + dpos 8 )
                = color ( __b buf + dpos 9 )
                = interlace ( __b buf + dpos 12 )
                = have_ihdr T
            } {}
            // PLTE
            ? & == t0 80 & == t1 76 & == t2 84 == t3 69 {
                : ~ i k 0
                ~ < k clen { ( vec_push [u] plte ( __b buf + dpos k ) ) = k + k 1 }
            } {}
            // tRNS
            ? & == t0 116 & == t1 82 & == t2 78 == t3 83 {
                : ~ i k 0
                ~ < k clen { ( vec_push [u] trnsb ( __b buf + dpos k ) ) = k + k 1 }
            } {}
            // IDAT
            ? & == t0 73 & == t1 68 & == t2 65 == t3 84 {
                : ~ i k 0
                ~ < k clen { ( vec_push [u] zdata ( __b buf + dpos k ) ) = k + k 1 }
            } {}
            // IEND
            ? & == t0 73 & == t1 69 & == t2 78 == t3 68 { = going F } {}
            = p + + dpos clen 4      // skip data + CRC
        }
    }

    : ~ b hdr_ok have_ihdr
    ? & & > width 0 > height 0 & <= width 1000000 <= height 1000000 {} { = hdr_ok F }
    ? > * width height 268435456 { = hdr_ok F }               // ≤ 256 Mpx
    ? & hdr_ok & ( __png_depth_ok color depth ) <= interlace 1 {} { = hdr_ok F }
    ? hdr_ok {} {
        ( vec_free [u] zdata ) ( vec_free [u] plte ) ( vec_free [u] trnsb )
        ^ @ ?Image { F }
    }

    // interpret tRNS for the colour type
    : ( Vec i ) trns ( vec_new [i] )
    : i tbn ( vec_len [u] trnsb )
    ? == color 3 {
        : ~ i k 0
        ~ < k tbn { ( vec_push [i] trns ( __b trnsb k ) ) = k + k 1 }
    } {
        // grey / RGB colour keys are 16-bit big-endian samples
        : ~ i k 0
        ~ < + k 1 tbn {
            ( vec_push [i] trns + * ( __b trnsb k ) 256 ( __b trnsb + k 1 ) )
            = k + k 2
        }
    }
    ( vec_free [u] trnsb )
    : i tn ( vec_len [i] trns )
    // colour keys compare raw (undownscaled) samples; for depth < 16 the key
    // is stored at source precision already, so equality just works.

    : i rch ( __png_raw_ch color )
    : ~ i outch rch
    ? == color 3 { = outch ? > tn 0 { 4 } { 3 } } {
        ? & > tn 0 || == color 0 == color 2 { = outch + rch 1 } {}
    }

    // zlib: strip the 2-byte header; inflate stops at the final block, so the
    // trailing adler32 is simply not read.
    : ( Vec u ) defl ( vec_new [u] )
    : i zn ( vec_len [u] zdata )
    : ~ i k 2
    ~ < k zn { ( vec_push [u] defl ( __b zdata k ) ) = k + k 1 }
    ( vec_free [u] zdata )
    : !( Vec u ) DeflateErr ir ( inflate defl )
    ( vec_free [u] defl )
    : ~ ( Vec u ) raw ( vec_new [u] )
    : ~ b infl_ok F
    ?? ir {
        T d → { ( vec_free [u] raw ) = raw d = infl_ok T }
        F _ → {}
    }
    ? infl_ok {} {
        ( vec_free [u] raw ) ( vec_free [u] plte ) ( vec_free [i] trns )
        ^ @ ?Image { F }
    }

    // Preflight: the inflated stream must hold every pass's rows BEFORE the
    // output raster is allocated — a 12-byte IDAT must not cost a 1 GB
    // zero-fill just because the IHDR claims huge dimensions.
    : i rawlen ( vec_len [u] raw )
    : ~ i want 0
    ? == interlace 0 {
        = want * height + / + * * width rch depth 7 8 1
    } {
        : ~ i pi0 0
        : ( Vec i ) ax ( vec_new [i] )
        ( vec_push [i] ax 0 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 0 ) ( vec_push [i] ax 2 ) ( vec_push [i] ax 0 ) ( vec_push [i] ax 1 ) ( vec_push [i] ax 0 )
        ( vec_push [i] ax 0 ) ( vec_push [i] ax 0 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 0 ) ( vec_push [i] ax 2 ) ( vec_push [i] ax 0 ) ( vec_push [i] ax 1 )
        ( vec_push [i] ax 8 ) ( vec_push [i] ax 8 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 2 ) ( vec_push [i] ax 2 ) ( vec_push [i] ax 1 )
        ( vec_push [i] ax 8 ) ( vec_push [i] ax 8 ) ( vec_push [i] ax 8 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 4 ) ( vec_push [i] ax 2 ) ( vec_push [i] ax 2 )
        ~ < pi0 7 {
            : i x0 ( __b_it ax pi0 )
            : i y0 ( __b_it ax + 7 pi0 )
            : i dxx ( __b_it ax + 14 pi0 )
            : i dyy ( __b_it ax + 21 pi0 )
            ? & > width x0 > height y0 {
                : i pw / + - width x0 - dxx 1 dxx
                : i ph / + - height y0 - dyy 1 dyy
                ? & > pw 0 > ph 0 {
                    = want + want * ph + / + * * pw rch depth 7 8 1
                } {}
            } {}
            = pi0 + pi0 1
        }
        ( vec_free [i] ax )
    }
    ? < rawlen want {
        ( vec_free [u] raw ) ( vec_free [u] plte ) ( vec_free [i] trns )
        ^ @ ?Image { F }
    } {}

    // zero-filled output raster
    : i total * * width height outch
    : ( Vec u ) out ( vec_with_cap [u] total )
    : ~ i z 0
    ~ < z total { ( vec_push [u] out 0 ) = z + z 1 }

    : ~ b ok T
    ? == interlace 0 {
        : i used ( __png_pass raw 0 width height 0 0 1 1 color depth plte trns tn out outch )
        ? < used 0 { = ok F } {}
    } {
        // Adam7: x0 y0 dx dy per pass
        : ( Vec i ) a7 ( vec_new [i] )
        ( vec_push [i] a7 0 ) ( vec_push [i] a7 0 ) ( vec_push [i] a7 8 ) ( vec_push [i] a7 8 )
        ( vec_push [i] a7 4 ) ( vec_push [i] a7 0 ) ( vec_push [i] a7 8 ) ( vec_push [i] a7 8 )
        ( vec_push [i] a7 0 ) ( vec_push [i] a7 4 ) ( vec_push [i] a7 4 ) ( vec_push [i] a7 8 )
        ( vec_push [i] a7 2 ) ( vec_push [i] a7 0 ) ( vec_push [i] a7 4 ) ( vec_push [i] a7 4 )
        ( vec_push [i] a7 0 ) ( vec_push [i] a7 2 ) ( vec_push [i] a7 2 ) ( vec_push [i] a7 4 )
        ( vec_push [i] a7 1 ) ( vec_push [i] a7 0 ) ( vec_push [i] a7 2 ) ( vec_push [i] a7 2 )
        ( vec_push [i] a7 0 ) ( vec_push [i] a7 1 ) ( vec_push [i] a7 1 ) ( vec_push [i] a7 2 )
        : ~ i off 0
        : ~ i pi 0
        ~ & ok < pi 7 {
            : i base * pi 4
            : i used ( __png_pass raw off width height ( __b_it a7 base ) ( __b_it a7 + base 1 ) ( __b_it a7 + base 2 ) ( __b_it a7 + base 3 ) color depth plte trns tn out outch )
            ? < used 0 { = ok F } { = off + off used }
            = pi + pi 1
        }
        ( vec_free [i] a7 )
    }

    ( vec_free [u] raw )
    ( vec_free [u] plte )
    ( vec_free [i] trns )
    ? ok {} { ( vec_free [u] out ) ^ @ ?Image { F } }
    ^ @ ?Image { T ( image_of width height outch out ) }
}

// ── Encode ────────────────────────────────────────────────────────────

@ __png_color_for i ch → i {
    ? == ch 1 { ^ 0 } {}
    ? == ch 2 { ^ 4 } {}
    ? == ch 4 { ^ 6 } {}
    ^ 2
}

@ __png_chunk ( Vec u ) out s type ( Vec u ) data → v {
    ( __push_u32be out ( vec_len [u] data ) )
    : ( Vec u ) td ( vec_new [u] )
    ( bytes_extend_str td type )
    ( vec_extend [u] td data )
    ( bytes_extend_str out type )
    ( vec_extend [u] out data )
    ( __push_u32be out ( crc32 td ) )
    ( vec_free [u] td )
}

// Encode an image as a non-interlaced, filter-0, 8-bit PNG.
@ png_encode Image im → ( Vec u ) {
    : i w . im width
    : i h . im height
    : i ch . im channels
    : i stride * w ch
    : ( Vec u ) out ( vec_new [u] )
    // signature
    ( vec_push [u] out 137 ) ( vec_push [u] out 80 ) ( vec_push [u] out 78 ) ( vec_push [u] out 71 )
    ( vec_push [u] out 13 ) ( vec_push [u] out 10 ) ( vec_push [u] out 26 ) ( vec_push [u] out 10 )
    // IHDR
    : ( Vec u ) ihdr ( vec_new [u] )
    ( __push_u32be ihdr w )
    ( __push_u32be ihdr h )
    ( vec_push [u] ihdr 8 )
    ( vec_push [u] ihdr ( __png_color_for ch ) )
    ( vec_push [u] ihdr 0 )
    ( vec_push [u] ihdr 0 )
    ( vec_push [u] ihdr 0 )
    ( __png_chunk out `IHDR` ihdr )
    ( vec_free [u] ihdr )
    // filtered scanlines (filter 0), then zlib-wrap
    : ( Vec u ) filt ( vec_with_cap [u] * h + stride 1 )
    : ~ i y 0
    ~ < y h {
        ( vec_push [u] filt 0 )
        : ~ i x 0
        ~ < x stride { ( vec_push [u] filt ( __b . im data + * y stride x ) ) = x + x 1 }
        = y + y 1
    }
    : ( Vec u ) comp ( deflate filt )
    : ( Vec u ) idat ( vec_new [u] )
    ( vec_push [u] idat 120 )       // zlib CMF 0x78
    ( vec_push [u] idat 156 )       // FLG 0x9c
    ( vec_extend [u] idat comp )
    ( __push_u32be idat ( adler32 filt ) )
    ( __png_chunk out `IDAT` idat )
    ( vec_free [u] filt )
    ( vec_free [u] comp )
    ( vec_free [u] idat )
    // IEND
    : ( Vec u ) iend ( vec_new [u] )
    ( __png_chunk out `IEND` iend )
    ( vec_free [u] iend )
    ^ out
}
