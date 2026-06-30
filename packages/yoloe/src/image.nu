// packages/yoloe/src/image.nu — image I/O + YOLO letterbox preprocessing.
//
// Reads/writes binary PPM (P6), letterboxes to the model's square input
// (aspect-preserving resize + grey pad), packs to an NCHW float tensor
// normalised to [0,1], and draws labelled boxes. An Image keeps the raw
// file bytes plus a pixel-data offset, so reading copies nothing; a fresh
// image (letterbox/blank) owns a new byte buffer.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`

& `c` @ nurl_poke_f32 *u base i idx f val → v

: Image { i w  i h  ( Vec u ) buf  i off }
// Letterbox result: the square image plus the transform back to original
// pixels (orig = (lb - pad) / scale).
: Letterbox { Image img  f scale  i padx  i pady }

@ img_w Image im → i { ^ . im w }
@ img_h Image im → i { ^ . im h }

@ img_get Image im i x i y i ch → i {
    : i xx ? < x 0 0 ? >= x . im w - . im w 1 x
    : i yy ? < y 0 0 ? >= y . im h - . im h 1 y
    : i idx + . im off + * + * yy . im w xx 3 ch
    ?? ( vec_get [u] . im buf idx ) { T b → ^ # i b F _ → ^ 0 }
}
@ img_set Image im i x i y i ch i val → v {
    ? | | < x 0 >= x . im w | < y 0 >= y . im h { ^ {} } {}
    : i idx + . im off + * + * y . im w x 3 ch
    : i cv ? < val 0 0 ? > val 255 255 val
    ( vec_set [u] . im buf idx # u cv )
}

// ── PPM (P6) ──────────────────────────────────────────────────────
@ __ws i b → b { ^ | | | == b 32 == b 10 == b 13 == b 9 }
@ __ppm_int ( Vec u ) buf i pos *u pnext → i {
    : ~ i p pos
    ~ ?? ( vec_get [u] buf p ) { T b → ( __ws # i b ) F _ → F } { = p + p 1 }
    : ~ i v 0
    ~ ?? ( vec_get [u] buf p ) { T b → & >= # i b 48 <= # i b 57 F _ → F } {
        : i d ?? ( vec_get [u] buf p ) { T b → - # i b 48 F _ → 0 }
        = v + * v 10 d
        = p + p 1
    }
    ( nurl_poke pnext 0 p )
    ^ v
}
@ ppm_read s path → ?Image {
    ?? ( read_file_bytes path ) {
        T buf → {
            : i b0 ?? ( vec_get [u] buf 0 ) { T x → # i x F _ → 0 }
            : i b1 ?? ( vec_get [u] buf 1 ) { T x → # i x F _ → 0 }
            ? | != b0 80 != b1 54 { ^ @ ?Image { F @ Image { 0 0 ( vec_new [u] ) 0 } } } {}
            : *u pc ( nurl_alloc 8 )
            : i w ( __ppm_int buf 2 pc )
            : i h ( __ppm_int buf ( nurl_peek pc 0 ) pc )
            : i mx ( __ppm_int buf ( nurl_peek pc 0 ) pc )
            : i off + ( nurl_peek pc 0 ) 1
            ^ @ ?Image { T @ Image { w h buf off } }
        }
        F _ → ^ @ ?Image { F @ Image { 0 0 ( vec_new [u] ) 0 } }
    }
}
@ img_blank i w i h i fill → Image {
    : i n * * w h 3
    : ( Vec u ) buf ( vec_new [u] )
    : ~ i k 0
    ~ < k n { ( vec_push [u] buf # u fill ) = k + k 1 }
    ^ @ Image { w h buf 0 }
}
@ ppm_write s path Image im → b {
    : String hdr ( string_from ( nurl_str_cat4 `P6\n` ( nurl_str_int . im w ) ` ` ( nurl_str_cat3 ( nurl_str_int . im h ) `\n` `255\n` ) ) )
    : ( Vec u ) out ( vec_new [u] )
    : s hs ( string_data hdr )
    : i hn ( nurl_str_len hs )
    : ~ i k 0
    ~ < k hn { ( vec_push [u] out # u ( nurl_str_get hs k ) ) = k + k 1 }
    : i n * * . im w . im h 3
    : ~ i j 0
    ~ < j n { ?? ( vec_get [u] . im buf + . im off j ) { T b → ( vec_push [u] out b ) F _ → {} } = j + j 1 }
    ?? ( write_file_bytes path out ) { T _ → ^ T F _ → ^ F }
}

// ── letterbox to S×S (aspect-preserving, grey 114 pad) ────────────
@ letterbox Image im i S → Letterbox {
    : i W . im w
    : i H . im h
    : f sx / # f S # f W
    : f sy / # f S # f H
    : f scale ? < sx sy sx sy
    : i nw # i * # f W scale
    : i nh # i * # f H scale
    : i padx / - S nw 2
    : i pady / - S nh 2
    : Image out ( img_blank S S 114 )
    : ~ i oy 0
    ~ < oy nh {
        : f srcyf / # f oy scale
        : i syi # i srcyf
        : ~ i ox 0
        ~ < ox nw {
            : f srcxf / # f ox scale
            : i sxi # i srcxf
            : ~ i c 0
            ~ < c 3 { ( img_set out + ox padx + oy pady c ( img_get im sxi syi c ) ) = c + c 1 }
            = ox + ox 1
        }
        = oy + oy 1
    }
    ^ @ Letterbox { out scale padx pady }
}

// Pack to NCHW float tensor normalised to [0,1].
@ img_to_nchw_norm Image im → *u {
    : i W . im w
    : i H . im h
    : *u host ( nurl_alloc * * * 3 H W 4 )
    : ~ i c 0
    ~ < c 3 {
        : ~ i y 0
        ~ < y H {
            : ~ i x 0
            ~ < x W {
                ( nurl_poke_f32 host + * c * H W + * y W x / # f ( img_get im x y c ) 255.0 )
                = x + x 1
            }
            = y + y 1
        }
        = c + c 1
    }
    ^ host
}

// ── drawing ───────────────────────────────────────────────────────
@ __hline Image im i x0 i x1 i y i r i gg i bb → v {
    : ~ i x x0
    ~ <= x x1 { ( img_set im x y 0 r ) ( img_set im x y 1 gg ) ( img_set im x y 2 bb ) = x + x 1 }
}
@ __vline Image im i x i y0 i y1 i r i gg i bb → v {
    : ~ i y y0
    ~ <= y y1 { ( img_set im x y 0 r ) ( img_set im x y 1 gg ) ( img_set im x y 2 bb ) = y + y 1 }
}
@ img_draw_rect Image im i x0 i y0 i x1 i y1 i r i gg i bb → v {
    : ~ i t 0
    ~ < t 3 {
        ( __hline im x0 x1 + y0 t r gg bb ) ( __hline im x0 x1 - y1 t r gg bb )
        ( __vline im + x0 t y0 y1 r gg bb ) ( __vline im - x1 t y0 y1 r gg bb )
        = t + t 1
    }
}
