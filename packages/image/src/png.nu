// image/png.nu — PNG decode + encode over the stdlib DEFLATE codec.
//
// Decode: 8-bit depth, non-interlaced, colour types 0 (grey), 2 (RGB),
// 3 (palette → expanded to RGB), 4 (grey+alpha), 6 (RGBA). Reconstructs all
// five scanline filters. Encode: 8-bit, non-interlaced, filter 0, colour type
// chosen from the image's channel count. Lossless — a decode→encode→decode
// round-trip reproduces the pixels exactly.
//
// Not yet: interlaced (Adam7) images, bit depths other than 8, and tRNS
// transparency on palette/grey images. `png_decode` returns None on those (and
// on malformed input); the codec never reads out of bounds.

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
        ? > + dpos clen n { = going F } {
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

    ? have_ihdr {} { ( vec_free [u] zdata ) ( vec_free [u] plte ) ^ @ ?Image { F } }
    ? & & == depth 8 == interlace 0 > ( __png_raw_ch color ) 0 {} {
        ( vec_free [u] zdata ) ( vec_free [u] plte )
        ^ @ ?Image { F }
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
    ?? ir {
        T d → { ( vec_free [u] raw ) = raw d }
        F _ → { ( vec_free [u] raw ) ( vec_free [u] plte ) ^ @ ?Image { F } }
    }

    : i rch ( __png_raw_ch color )
    : i stride * width rch
    : i expect * height + stride 1
    ? >= ( vec_len [u] raw ) expect {} {
        ( vec_free [u] raw ) ( vec_free [u] plte )
        ^ @ ?Image { F }
    }

    // Unfilter into a stride-packed buffer (no per-row filter byte).
    : ( Vec u ) recon ( vec_with_cap [u] * height stride )
    : ~ i y 0
    ~ < y height {
        : i rowpos * y + stride 1
        : i ft ( __b raw rowpos )
        : i base + rowpos 1
        : i prevbase - base + stride 1     // start of previous recon row
        : ~ i x 0
        ~ < x stride {
            : i fv ( __b raw + base x )
            : i left ? >= x rch { ( __b recon - + * y stride x rch ) } { 0 }
            : i up ? > y 0 { ( __b recon - + * y stride x stride ) } { 0 }
            : i ul ? & > y 0 >= x rch { ( __b recon - - + * y stride x rch stride ) } { 0 }
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
    ( vec_free [u] raw )

    // Palette → RGB expansion; everything else keeps its raw channels.
    ? == color 3 {
        : ( Vec u ) rgb ( vec_with_cap [u] * * width height 3 )
        : i np * width height
        : ~ i j 0
        ~ < j np {
            : i idx * ( __b recon j ) 3
            ( vec_push [u] rgb ( __b plte idx ) )
            ( vec_push [u] rgb ( __b plte + idx 1 ) )
            ( vec_push [u] rgb ( __b plte + idx 2 ) )
            = j + j 1
        }
        ( vec_free [u] recon )
        ( vec_free [u] plte )
        ^ @ ?Image { T ( image_of width height 3 rgb ) }
    } {}
    ( vec_free [u] plte )
    ^ @ ?Image { T ( image_of width height rch recon ) }
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
