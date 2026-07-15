// image/core.nu — the Image type, byte helpers, and PPM (P5/P6).
//
// An Image is a tightly-packed, row-major, 8-bit-per-channel raster:
//   channels 1 = grayscale, 3 = RGB, 4 = RGBA.
// data holds width*height*channels bytes. Every codec in the package decodes
// into, and encodes from, this one representation.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`

: Image {
    i width
    i height
    i channels
    ( Vec u ) data
}

// ── Failure reason (stb_image-style) ──────────────────────────────────
//
// Decoders answer with ?Image; when you get None, ( image_error ) says
// why — a static string, valid until the next decode call. Not
// thread-safe (one global slot), like stbi_failure_reason.

: ~ s __img_err ``

@ image_error → s { ^ __img_err }

@ _img_set_err s msg → v { = __img_err msg }

// ── Construction ──────────────────────────────────────────────────────

// A zero-filled image of the given geometry.
@ image_new i w i h i ch → Image {
    : i n * * w h ch
    : ( Vec u ) d ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] d 0 ) = k + k 1 }
    ^ @ Image { w h ch d }
}

// Adopt an existing byte buffer (moved in; not copied).
@ image_of i w i h i ch ( Vec u ) data → Image {
    ^ @ Image { w h ch data }
}

@ image_free Image im → v { ( vec_free [u] . im data ) }

@ image_width Image im → i { ^ . im width }

@ image_height Image im → i { ^ . im height }

@ image_channels Image im → i { ^ . im channels }

// ── Byte helpers ──────────────────────────────────────────────────────

// Unsigned byte at `pos` (0 when out of range).
@ _byte ( Vec u ) buf i pos → i {
    ?? ( vec_get [u] buf pos ) { T v → { ^ # i v } F _ → { ^ 0 } }
}

@ _push_u16be ( Vec u ) out i v → v {
    ( vec_push [u] out & / v 256 255 )
    ( vec_push [u] out & v 255 )
}

@ _push_u32be ( Vec u ) out i v → v {
    ( vec_push [u] out & / v 16777216 255 )
    ( vec_push [u] out & / v 65536 255 )
    ( vec_push [u] out & / v 256 255 )
    ( vec_push [u] out & v 255 )
}

@ _u32be ( Vec u ) buf i pos → i {
    ^ + + + * ( _byte buf pos ) 16777216 * ( _byte buf + pos 1 ) 65536 * ( _byte buf + pos 2 ) 256 ( _byte buf + pos 3 )
}

// ── Pixel access ──────────────────────────────────────────────────────

// -1 when (x,y,c) is outside the raster — callers treat that as "no pixel"
// (image_get reads 0, image_set is a no-op). Without the guard an x just past
// the row edge would silently wrap onto the next row.
@ __px_idx Image im i x i y i c → i {
    ? || || < x 0 < y 0 || >= x . im width >= y . im height { ^ -1 } {}
    ? || < c 0 >= c . im channels { ^ -1 } {}
    : i pix + * y . im width x
    ^ + * pix . im channels c
}

@ image_get Image im i x i y i c → i { ^ ( _byte . im data ( __px_idx im x y c ) ) }

@ image_set Image im i x i y i c i v → v {
    ( vec_set [u] . im data ( __px_idx im x y c ) & v 255 )
}

// ── PPM (binary P6 = RGB, P5 = grayscale) ─────────────────────────────

// Skip ASCII whitespace and #-comments from `p`; return the next position.
@ __ppm_skip ( Vec u ) buf i n i p → i {
    : ~ i q p
    : ~ b going T
    ~ going {
        ? >= q n { = going F } {
            : i c ( _byte buf q )
            ? == c 35 {
                ~ & < q n != ( _byte buf q ) 10 { = q + q 1 }
            } {
                ? || == c 32 || == c 9 || == c 10 == c 13 { = q + q 1 } { = going F }
            }
        }
    }
    ^ q
}

// Read a decimal integer starting at `p` (after skipping ws); the position
// after the number is written into `posp[0]`.
@ __ppm_int ( Vec u ) buf i n i p * u posp → i {
    : ~ i q ( __ppm_skip buf n p )
    : ~ i val 0
    ~ & < q n & >= ( _byte buf q ) 48 <= ( _byte buf q ) 57 {
        = val + * val 10 - ( _byte buf q ) 48
        = q + q 1
    }
    ( nurl_poke posp 0 q )
    ^ val
}

@ ppm_decode ( Vec u ) buf → ?Image {
    ( _img_set_err `` )
    : i n ( vec_len [u] buf )
    ? < n 2 { ( _img_set_err `not a PPM` ) ^ @ ?Image { F } } {}
    ? == ( _byte buf 0 ) 80 {} { ( _img_set_err `not a PPM` ) ^ @ ?Image { F } }
    : i kind ( _byte buf 1 )
    : ~ i ch 3
    ? == kind 54 { = ch 3 } {
        ? == kind 53 { = ch 1 } { ( _img_set_err `PPM: only binary P5/P6 supported` ) ^ @ ?Image { F } }
    }
    : *u pc ( nurl_alloc 8 )
    : i w ( __ppm_int buf n 2 pc )
    : i h ( __ppm_int buf n ( nurl_peek pc 0 ) pc )
    : i mx ( __ppm_int buf n ( nurl_peek pc 0 ) pc )
    // pixel data starts one whitespace byte after maxval
    : i start + ( nurl_peek pc 0 ) 1
    ( nurl_free # s pc )
    ? || <= w 0 || <= h 0 != mx 255 { ( _img_set_err `PPM: malformed header (needs maxval 255)` ) ^ @ ?Image { F } } {}
    ? || || > w 1000000 > h 1000000 > * w h 268435456 { ( _img_set_err `PPM: dimensions too large` ) ^ @ ?Image { F } } {}
    : i need * * w h ch
    ? > + start need n {} {}  // tolerate exact-or-more
    ? < - n start need { ( _img_set_err `PPM: truncated pixel data` ) ^ @ ?Image { F } } {}
    : ( Vec u ) d ( vec_with_cap [u] need )
    : ~ i k 0
    ~ < k need { ( vec_push [u] d ( _byte buf + start k ) ) = k + k 1 }
    ^ @ ?Image { T ( image_of w h ch d ) }
}

// Encode as binary PPM: 3/4-channel → P6 (alpha dropped), 1-channel → P5.
@ ppm_encode Image im → ( Vec u ) {
    : i w . im width
    : i h . im height
    : i ch . im channels
    : b gray == ch 1
    : ( Vec u ) out ( vec_with_cap [u] + 32 * * w h ? gray { 1 } { 3 } )
    ( bytes_extend_str out ? gray { `P5\n` } { `P6\n` } )
    : String hdr ( string_new )
    ( string_push_int hdr w )
    ( string_push_char hdr 32 )
    ( string_push_int hdr h )
    ( string_push_str hdr `\n255\n` )
    ( bytes_extend_str out ( string_data hdr ) )
    ( string_free hdr )
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            ? gray {
                ( vec_push [u] out ( image_get im x y 0 ) )
            } {
                ( vec_push [u] out ( image_get im x y 0 ) )
                ( vec_push [u] out ( image_get im x y ? >= ch 3 { 1 } { 0 } ) )
                ( vec_push [u] out ( image_get im x y ? >= ch 3 { 2 } { 0 } ) )
            }
            = x + x 1
        }
        = y + y 1
    }
    ^ out
}
