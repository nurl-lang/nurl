// image/ops.nu — raster operations on the Image type.
//
// Everything a downstream package used to hand-roll: resize (nearest /
// bilinear / box-average), crop, flips, quarter-turn rotations, channel
// conversion, fill, rectangle / line drawing, and blit with alpha.
//
// Colours are one packed integer, 0xRRGGBBAA (e.g. opaque red 0xFF0000FF),
// mapped onto whatever channel count the target image has: greyscale targets
// take the BT.601 luma, images without an alpha channel drop A. Reads from a
// greyscale image replicate the grey value into R, G and B; a missing alpha
// channel reads as 255.
//
// Transform functions (`image_resize*`, `image_crop`, flips, rotations,
// `image_convert`, `image_clone`) return a NEW image — free both. Drawing
// functions (`image_fill*`, `image_draw_*`, `image_blit`) mutate in place,
// clip to the raster, and overwrite (no blending) — except `image_blit`,
// which source-over-blends when the source has an alpha channel.

$ `stdlib/core/vec.nu`
$ `core.nu`

// BT.601 integer luma (77 + 150 + 29 = 256).
@ __luma i r i g i b → i { ^ >> + + + * 77 r * 150 g * 29 b 128 8 }

@ __clampi i v i lo i hi → i {
    ? < v lo { ^ lo } {}
    ? > v hi { ^ hi } {}
    ^ v
}

// ── Packed-pixel access ───────────────────────────────────────────────

// Read pixel (x,y) as packed 0xRRGGBBAA regardless of the image's channel
// count (grey replicates into R/G/B, missing alpha reads 255). Out of
// bounds every stored channel reads 0.
@ image_get_rgba Image im i x i y → i {
    : i ch . im channels
    ? <= ch 2 {
        : i g ( image_get im x y 0 )
        : i a ? == ch 2 { ( image_get im x y 1 ) } { 255 }
        ^ | | | << g 24 << g 16 << g 8 a
    } {}
    : i r ( image_get im x y 0 )
    : i g2 ( image_get im x y 1 )
    : i b2 ( image_get im x y 2 )
    : i a2 ? == ch 4 { ( image_get im x y 3 ) } { 255 }
    ^ | | | << r 24 << g2 16 << b2 8 a2
}

// Write packed 0xRRGGBBAA into pixel (x,y), mapping onto the image's
// channels (grey targets take the luma; a missing alpha channel drops A).
// Out-of-bounds writes are ignored.
@ image_set_rgba Image im i x i y i rgba → v {
    : i r & >> rgba 24 255
    : i g & >> rgba 16 255
    : i b & >> rgba 8 255
    : i a & rgba 255
    : i ch . im channels
    ? <= ch 2 {
        ( image_set im x y 0 ( __luma r g b ) )
        ? == ch 2 { ( image_set im x y 1 a ) } {}
    } {
        ( image_set im x y 0 r )
        ( image_set im x y 1 g )
        ( image_set im x y 2 b )
        ? == ch 4 { ( image_set im x y 3 a ) } {}
    }
}

// ── Clone / convert / crop ────────────────────────────────────────────

@ image_clone Image im → Image {
    : ( Vec u ) d ( vec_new [u] )
    ( vec_extend [u] d . im data )
    ^ ( image_of . im width . im height . im channels d )
}

// Convert to `ch` channels (1 grey, 2 grey+alpha, 3 RGB, 4 RGBA).
// Grey ↔ RGB uses BT.601 luma; added alpha is 255; dropped alpha is dropped.
@ image_convert Image im i ch → Image {
    : i w . im width
    : i h . im height
    : Image out ( image_new w h ch )
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            ( image_set_rgba out x y ( image_get_rgba im x y ) )
            = x + x 1
        }
        = y + y 1
    }
    ^ out
}

// Copy the w×h window whose top-left corner is (x,y). The window is clipped
// to the source; a fully-outside window yields a 0×0 image.
@ image_crop Image im i x i y i w i h → Image {
    : i x0 ( __clampi x 0 . im width )
    : i y0 ( __clampi y 0 . im height )
    : i x1 ( __clampi + x w 0 . im width )
    : i y1 ( __clampi + y h 0 . im height )
    : i cw ? > x1 x0 { - x1 x0 } { 0 }
    : i chh ? > y1 y0 { - y1 y0 } { 0 }
    : i c . im channels
    : ( Vec u ) d ( vec_with_cap [u] * * cw chh c )
    : ~ i yy 0
    ~ < yy chh {
        : ~ i xx 0
        ~ < xx cw {
            : ~ i k 0
            ~ < k c {
                ( vec_push [u] d ( image_get im + x0 xx + y0 yy k ) )
                = k + k 1
            }
            = xx + xx 1
        }
        = yy + yy 1
    }
    ^ ( image_of cw chh c d )
}

// ── Flips and quarter-turn rotations ──────────────────────────────────

@ __image_map_px Image im i w i h b swap b fx b fy → Image {
    // out(x,y) = im( srcx, srcy ) where (srcx,srcy) = (y,x) if swap, then
    // mirrored by fx/fy over the SOURCE raster.
    : i c . im channels
    : ( Vec u ) d ( vec_with_cap [u] * * w h c )
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : ~ i sx ? swap { y } { x }
            : ~ i sy ? swap { x } { y }
            ? fx { = sx - - . im width 1 sx } {}
            ? fy { = sy - - . im height 1 sy } {}
            : ~ i k 0
            ~ < k c { ( vec_push [u] d ( image_get im sx sy k ) ) = k + k 1 }
            = x + x 1
        }
        = y + y 1
    }
    ^ ( image_of w h c d )
}

@ image_flip_h Image im → Image { ^ ( __image_map_px im . im width . im height F T F ) }
@ image_flip_v Image im → Image { ^ ( __image_map_px im . im width . im height F F T ) }
// Clockwise quarter turns.
@ image_rot90  Image im → Image { ^ ( __image_map_px im . im height . im width T F T ) }
@ image_rot180 Image im → Image { ^ ( __image_map_px im . im width . im height F T T ) }
@ image_rot270 Image im → Image { ^ ( __image_map_px im . im height . im width T T F ) }

// ── Resize ────────────────────────────────────────────────────────────

// Nearest neighbour: out(x,y) = in( x*sw/nw, y*sh/nh ). Exact, blocky.
@ image_resize_nearest Image im i nw i nh → Image {
    ? || <= nw 0 <= nh 0 { ^ ( image_new 0 0 . im channels ) } {}
    : i c . im channels
    : ( Vec u ) d ( vec_with_cap [u] * * nw nh c )
    : ~ i y 0
    ~ < y nh {
        : i sy / * y . im height nh
        : ~ i x 0
        ~ < x nw {
            : i sx / * x . im width nw
            : ~ i k 0
            ~ < k c { ( vec_push [u] d ( image_get im sx sy k ) ) = k + k 1 }
            = x + x 1
        }
        = y + y 1
    }
    ^ ( image_of nw nh c d )
}

// Bilinear, edge-clamped, pixel-centre aligned. The right default for
// upscaling and mild downscaling; for thumbnails (large shrink) prefer
// image_resize_area, which averages instead of skipping.
@ image_resize Image im i nw i nh → Image {
    ? || <= nw 0 <= nh 0 { ^ ( image_new 0 0 . im channels ) } {}
    : i w . im width
    : i h . im height
    : i c . im channels
    : Image out ( image_new nw nh c )
    : f sx / # f w # f nw
    : f sy / # f h # f nh
    : ~ i oy 0
    ~ < oy nh {
        : ~ f fy - * + # f oy 0.5 sy 0.5
        ? < fy 0.0 { = fy 0.0 } {}
        : ~ i y0 # i fy
        ? > y0 - h 1 { = y0 - h 1 } {}
        : i y1 ? < + y0 1 h { + y0 1 } { y0 }
        : f wy - fy # f y0
        : ~ i ox 0
        ~ < ox nw {
            : ~ f fx - * + # f ox 0.5 sx 0.5
            ? < fx 0.0 { = fx 0.0 } {}
            : ~ i x0 # i fx
            ? > x0 - w 1 { = x0 - w 1 } {}
            : i x1 ? < + x0 1 w { + x0 1 } { x0 }
            : f wx - fx # f x0
            : ~ i k 0
            ~ < k c {
                : f p00 # f ( image_get im x0 y0 k )
                : f p10 # f ( image_get im x1 y0 k )
                : f p01 # f ( image_get im x0 y1 k )
                : f p11 # f ( image_get im x1 y1 k )
                : f top + * p00 - 1.0 wx * p10 wx
                : f bot + * p01 - 1.0 wx * p11 wx
                ( image_set out ox oy k # i + + * top - 1.0 wy * bot wy 0.5 )
                = k + k 1
            }
            = ox + ox 1
        }
        = oy + oy 1
    }
    ^ out
}

// Box average: each output pixel is the mean of its source rectangle.
// Exact anti-aliased downscale for integer factors (a 2× shrink averages
// each 2×2 block); the right choice for thumbnails.
@ image_resize_area Image im i nw i nh → Image {
    ? || <= nw 0 <= nh 0 { ^ ( image_new 0 0 . im channels ) } {}
    : i w . im width
    : i h . im height
    : i c . im channels
    : Image out ( image_new nw nh c )
    : ~ i oy 0
    ~ < oy nh {
        : i ys0 / * oy h nh
        : ~ i ys1 / * + oy 1 h nh
        ? > ys1 ys0 {} { = ys1 + ys0 1 }
        : ~ i ox 0
        ~ < ox nw {
            : i xs0 / * ox w nw
            : ~ i xs1 / * + ox 1 w nw
            ? > xs1 xs0 {} { = xs1 + xs0 1 }
            : i cnt * - xs1 xs0 - ys1 ys0
            : ~ i k 0
            ~ < k c {
                : ~ i sum 0
                : ~ i yy ys0
                ~ < yy ys1 {
                    : ~ i xx xs0
                    ~ < xx xs1 { = sum + sum ( image_get im xx yy k ) = xx + xx 1 }
                    = yy + yy 1
                }
                ( image_set out ox oy k / + sum / cnt 2 cnt )
                = k + k 1
            }
            = ox + ox 1
        }
        = oy + oy 1
    }
    ^ out
}

// ── Fill and drawing (in place, clipped, overwrite) ───────────────────

@ image_fill Image im i rgba → v {
    : ~ i y 0
    ~ < y . im height {
        : ~ i x 0
        ~ < x . im width { ( image_set_rgba im x y rgba ) = x + x 1 }
        = y + y 1
    }
}

// Fill the rectangle with corners (x0,y0)–(x1,y1), inclusive.
@ image_fill_rect Image im i x0 i y0 i x1 i y1 i rgba → v {
    : i ax ( __clampi ? < x0 x1 { x0 } { x1 } 0 - . im width 1 )
    : i bx ( __clampi ? < x0 x1 { x1 } { x0 } 0 - . im width 1 )
    : i ay ( __clampi ? < y0 y1 { y0 } { y1 } 0 - . im height 1 )
    : i by ( __clampi ? < y0 y1 { y1 } { y0 } 0 - . im height 1 )
    ? || <= . im width 0 <= . im height 0 { ^ } {}
    : ~ i y ay
    ~ <= y by {
        : ~ i x ax
        ~ <= x bx { ( image_set_rgba im x y rgba ) = x + x 1 }
        = y + y 1
    }
}

// Rectangle outline with corners (x0,y0)–(x1,y1) inclusive, `t` pixels
// thick, growing inward.
@ image_draw_rect Image im i x0 i y0 i x1 i y1 i t i rgba → v {
    ? <= t 0 { ^ } {}
    : i ax ? < x0 x1 { x0 } { x1 }
    : i bx ? < x0 x1 { x1 } { x0 }
    : i ay ? < y0 y1 { y0 } { y1 }
    : i by ? < y0 y1 { y1 } { y0 }
    : i tt - t 1
    ( image_fill_rect im ax ay bx + ay tt rgba )
    ( image_fill_rect im ax - by tt bx by rgba )
    ( image_fill_rect im ax ay + ax tt by rgba )
    ( image_fill_rect im - bx tt ay bx by rgba )
}

// Bresenham line from (x0,y0) to (x1,y1), clipped per pixel.
@ image_draw_line Image im i x0 i y0 i x1 i y1 i rgba → v {
    : i dx ? > x1 x0 { - x1 x0 } { - x0 x1 }
    : i dy ? > y1 y0 { - y0 y1 } { - y1 y0 }     // -abs(dy)
    : i stx ? < x0 x1 { 1 } { -1 }
    : i sty ? < y0 y1 { 1 } { -1 }
    : ~ i err + dx dy
    : ~ i x x0
    : ~ i y y0
    : ~ b going T
    ~ going {
        ( image_set_rgba im x y rgba )
        ? & == x x1 == y y1 { = going F } {
            : i e2 * 2 err
            ? >= e2 dy { = err + err dy = x + x stx } {}
            ? <= e2 dx { = err + err dx = y + y sty } {}
        }
    }
}

// ── Blit ──────────────────────────────────────────────────────────────

// Copy `src` onto `dst` with its top-left corner at (dx,dy), clipped to the
// destination. Channel counts may differ (pixels are mapped like
// image_set_rgba). If the source has an alpha channel the copy is
// source-over blended; otherwise it overwrites.
@ image_blit Image dst Image src i dx i dy → v {
    : b blend ? || == . src channels 2 == . src channels 4 { T } { F }
    : ~ i y 0
    ~ < y . src height {
        : i ty + dy y
        ? || < ty 0 >= ty . dst height {} {
            : ~ i x 0
            ~ < x . src width {
                : i tx + dx x
                ? || < tx 0 >= tx . dst width {} {
                    : i sp ( image_get_rgba src x y )
                    ? blend {
                        : i a & sp 255
                        ? == a 0 {} {
                        ? == a 255 { ( image_set_rgba dst tx ty sp ) } {
                            : i dp ( image_get_rgba dst tx ty )
                            : i r ( __blend8 & >> sp 24 255 & >> dp 24 255 a )
                            : i g ( __blend8 & >> sp 16 255 & >> dp 16 255 a )
                            : i b ( __blend8 & >> sp 8 255 & >> dp 8 255 a )
                            : i oa ( __blend8 255 & dp 255 a )
                            ( image_set_rgba dst tx ty | | | << r 24 << g 16 << b 8 oa )
                        } }
                    } {
                        ( image_set_rgba dst tx ty sp )
                    }
                }
                = x + x 1
            }
        }
        = y + y 1
    }
}

// (s*a + d*(255-a)) / 255, rounded.
@ __blend8 i sv i dv i a → i {
    ^ / + + * sv a * dv - 255 a 127 255
}
