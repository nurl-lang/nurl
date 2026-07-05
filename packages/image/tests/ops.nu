// tests/ops.nu — deterministic checks for image/ops.nu. No references
// needed: every operation here has an exact expected answer.
//   ops            → prints "PASS <name>" per check, exits 1 on any failure

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `src/image.nu`

: ~ i g_fail 0

@ check b ok s name → v {
    ? ok { ( nurl_print `PASS ` ) } { ( nurl_print `FAIL ` ) = g_fail 1 }
    ( puts name )
}

// A 4×3 RGB test card: pixel (x,y) = (x*40, y*70, x+y).
@ card → Image {
    : Image im ( image_new 4 3 3 )
    : ~ i y 0
    ~ < y 3 {
        : ~ i x 0
        ~ < x 4 {
            ( image_set im x y 0 * x 40 )
            ( image_set im x y 1 * y 70 )
            ( image_set im x y 2 + x y )
            = x + x 1
        }
        = y + y 1
    }
    ^ im
}

@ px_eq Image a i ax i ay Image b i bx i by → b {
    ^ == ( image_get_rgba a ax ay ) ( image_get_rgba b bx by )
}

@ main → i {
    : Image im ( card )

    // ── packed pixel access ───────────────────────────────────────────
    ( check == ( image_get_rgba im 2 1 ) | | | << 80 24 << 70 16 << 3 8 255 `get_rgba packs 0xRRGGBBAA` )
    ( check == ( image_get_rgba im 9 9 ) 255 `get_rgba out of bounds reads channels as 0` )
    ( image_set_rgba im 0 0 305419896 )      // 0x12345678
    ( check & & == ( image_get im 0 0 0 ) 18 == ( image_get im 0 0 1 ) 52 == ( image_get im 0 0 2 ) 86 `set_rgba maps channels` )
    // x == width used to wrap onto the next row — must be ignored now
    : i keep ( image_get_rgba im 0 1 )
    ( image_set im 4 0 0 99 )
    ( check == ( image_get_rgba im 0 1 ) keep `image_set past the row edge does not wrap` )
    ( image_set im 0 0 0 0 ) ( image_set im 0 0 1 0 ) ( image_set im 0 0 2 0 )

    // ── clone / convert ───────────────────────────────────────────────
    : Image cl ( image_clone im )
    ( check & ( px_eq cl 1 1 im 1 1 ) == ( image_width cl ) 4 `clone equal` )
    ( image_set cl 1 1 0 9 )
    ( check ! ( px_eq cl 1 1 im 1 1 ) `clone is a deep copy` )
    ( image_free cl )

    : Image gr ( image_convert im 1 )
    // luma of (80,70,3) = (77*80+150*70+29*3+128)>>8 = (6160+10500+87+128)>>8 = 65
    ( check & == ( image_channels gr ) 1 == ( image_get gr 2 1 0 ) 65 `convert to grey uses BT.601 luma` )
    : Image ga ( image_convert gr 2 )
    ( check & == ( image_channels ga ) 2 & == ( image_get ga 2 1 0 ) 65 == ( image_get ga 2 1 1 ) 255 `grey→grey+alpha adds a=255` )
    : Image rgba ( image_convert im 4 )
    ( check & == ( image_channels rgba ) 4 & ( px_eq rgba 2 1 im 2 1 ) == ( image_get rgba 2 1 3 ) 255 `rgb→rgba keeps pixels` )
    ( image_free gr ) ( image_free ga ) ( image_free rgba )

    // ── crop ──────────────────────────────────────────────────────────
    : Image cr ( image_crop im 1 1 2 2 )
    ( check & & == ( image_width cr ) 2 == ( image_height cr ) 2 ( px_eq cr 0 0 im 1 1 ) `crop copies the window` )
    ( image_free cr )
    : Image cr2 ( image_crop im 3 2 5 5 )
    ( check & & == ( image_width cr2 ) 1 == ( image_height cr2 ) 1 ( px_eq cr2 0 0 im 3 2 ) `crop clips to the raster` )
    ( image_free cr2 )
    : Image cr3 ( image_crop im 10 10 2 2 )
    ( check == * ( image_width cr3 ) ( image_height cr3 ) 0 `fully-outside crop is 0×0` )
    ( image_free cr3 )

    // ── flips and rotations ───────────────────────────────────────────
    : Image fh ( image_flip_h im )
    ( check ( px_eq fh 0 1 im 3 1 ) `flip_h mirrors x` )
    : Image fh2 ( image_flip_h fh )
    ( check ( px_eq fh2 1 2 im 1 2 ) `flip_h twice is identity` )
    ( image_free fh ) ( image_free fh2 )
    : Image fv ( image_flip_v im )
    ( check ( px_eq fv 2 0 im 2 2 ) `flip_v mirrors y` )
    ( image_free fv )

    : Image r90 ( image_rot90 im )
    // CW: src(x,y) → dst(H-1-y, x); src(3,0) → dst(2,3)
    ( check & & == ( image_width r90 ) 3 == ( image_height r90 ) 4 ( px_eq r90 2 3 im 3 0 ) `rot90 clockwise` )
    : Image r180 ( image_rot180 im )
    ( check ( px_eq r180 0 0 im 3 2 ) `rot180` )
    : Image r270 ( image_rot270 im )
    ( check & == ( image_width r270 ) 3 ( px_eq r270 0 0 im 3 0 ) `rot270` )
    : Image r90x4a ( image_rot90 r90 )
    : Image r90x4b ( image_rot90 r90x4a )
    : Image r90x4 ( image_rot90 r90x4b )
    ( check & ( px_eq r90x4 1 2 im 1 2 ) ( px_eq r90x4 3 0 im 3 0 ) `rot90 four times is identity` )
    ( image_free r90 ) ( image_free r180 ) ( image_free r270 )
    ( image_free r90x4a ) ( image_free r90x4b ) ( image_free r90x4 )

    // ── resize ────────────────────────────────────────────────────────
    : Image n2 ( image_resize_nearest im 8 6 )
    ( check & ( px_eq n2 0 0 im 0 0 ) & ( px_eq n2 7 5 im 3 2 ) ( px_eq n2 4 2 im 2 1 ) `nearest 2× picks source pixels` )
    ( image_free n2 )

    // bilinear on a constant image stays constant
    : Image flat ( image_new 5 4 3 )
    ( image_fill flat 2864434431 )           // 0xAABBCCFF
    : Image fb ( image_resize flat 13 9 )
    ( check & == ( image_get fb 6 4 0 ) 170 & == ( image_get fb 6 4 1 ) 187 == ( image_get fb 12 8 2 ) 204 `bilinear keeps a constant image constant` )
    ( image_free flat ) ( image_free fb )

    // bilinear 2× of a 2-px gradient: centres interpolate 25/75%
    : Image g2 ( image_new 2 1 1 )
    ( image_set g2 0 0 0 0 ) ( image_set g2 1 0 0 200 )
    : Image g4 ( image_resize g2 4 1 )
    ( check & & == ( image_get g4 0 0 0 ) 0 == ( image_get g4 1 0 0 ) 50 & == ( image_get g4 2 0 0 ) 150 == ( image_get g4 3 0 0 ) 200 `bilinear interpolates pixel centres` )
    ( image_free g2 ) ( image_free g4 )

    // area 2× shrink averages each 2×2 block exactly
    : Image big ( image_new 4 2 1 )
    ( image_set big 0 0 0 10 ) ( image_set big 1 0 0 20 ) ( image_set big 0 1 0 30 ) ( image_set big 1 1 0 40 )
    ( image_set big 2 0 0 100 ) ( image_set big 3 0 0 100 ) ( image_set big 2 1 0 200 ) ( image_set big 3 1 0 204 )
    : Image sm ( image_resize_area big 2 1 )
    ( check & == ( image_get sm 0 0 0 ) 25 == ( image_get sm 1 0 0 ) 151 `area shrink is the exact block mean` )
    ( image_free big ) ( image_free sm )

    // ── fill / rect / line ────────────────────────────────────────────
    : Image cv ( image_new 8 8 3 )
    ( image_fill_rect cv 2 2 5 5 4278190335 )      // 0xFF0000FF red
    ( check & & == ( image_get cv 2 2 0 ) 255 == ( image_get cv 5 5 0 ) 255 == ( image_get cv 6 5 0 ) 0 `fill_rect inclusive corners` )
    ( image_fill_rect cv -3 -3 20 20 255 )          // clipped full clear
    ( check == ( image_get_rgba cv 7 7 ) 255 `fill_rect clips` )
    ( image_draw_rect cv 1 1 6 6 2 65535 )          // 0x0000FFFF blue, t=2
    ( check & & == ( image_get cv 2 2 2 ) 255 == ( image_get cv 3 3 2 ) 0 & == ( image_get cv 6 1 2 ) 255 == ( image_get cv 3 2 2 ) 255 `draw_rect outline thickness 2` )
    ( image_fill cv 0 )
    ( image_draw_line cv 0 0 7 7 16711935 )         // 0x00FF00FF green diagonal
    ( check & & == ( image_get cv 0 0 1 ) 255 == ( image_get cv 4 4 1 ) 255 & == ( image_get cv 7 7 1 ) 255 == ( image_get cv 4 5 1 ) 0 `draw_line diagonal` )
    ( image_draw_line cv -5 3 30 3 255 )            // clipped horizontal: must not crash
    ( check == ( image_get_rgba cv 7 3 ) 255 `draw_line clips per pixel` )
    ( image_free cv )

    // ── blit ──────────────────────────────────────────────────────────
    : Image bg ( image_new 6 6 3 )
    ( image_fill bg | << 100 24 255 )               // r=100 backdrop
    : Image sp ( image_new 2 2 4 )
    ( image_fill sp | | << 200 24 << 255 16 255 )   // opaque r=200,g=255
    ( image_set sp 1 1 3 0 )                        // one transparent px
    ( image_set sp 0 1 3 128 )                      // one half-alpha px
    ( image_blit bg sp 2 2 )
    ( check == ( image_get bg 2 2 0 ) 200 `blit copies opaque pixels` )
    ( check == ( image_get bg 3 3 0 ) 100 `blit skips fully transparent` )
    // half alpha: (200*128 + 100*127 + 127)/255 = 150
    ( check == ( image_get bg 2 3 0 ) 150 `blit source-over blends` )
    ( image_blit bg sp 5 5 )                        // clipped bottom-right
    ( check == ( image_get bg 5 5 0 ) 200 `blit clips` )
    ( image_free sp )
    // 3-channel source overwrites
    : Image sp3 ( image_new 2 2 3 )
    ( image_blit bg sp3 0 0 )
    ( check == ( image_get bg 0 0 0 ) 0 `blit without alpha overwrites` )
    ( image_free sp3 ) ( image_free bg )

    ( image_free im )
    ? == g_fail 0 { ( puts `== ops: PASS` ) } { ( puts `== ops: FAIL` ) }
    ^ g_fail
}
