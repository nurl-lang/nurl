// packages/yoloe/src/decode.nu — turn YOLOE's output0 into boxes.
//
// output0 is [1, 4+nc+nm, na] (na = 8400 anchors over 3 scales): the first
// 4 channels are the box (cx,cy,w,h, already decoded to pixels in the
// letterboxed frame), the next nc are per-class scores (already sigmoid),
// the rest are segmentation mask coefficients (ignored here). For each
// anchor we take the best class above a threshold, then non-max suppress.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

// A detection in letterboxed-pixel centre/size coordinates. `ai` is the
// anchor index it came from — needed to read the 32 mask coefficients
// (output0 channels 4+nc..4+nc+nm at that anchor) for segmentation.
: Detection { i cls  f score  f cx  f cy  f w  f h  i ai }

// value at (channel, anchor) for a [1, C, na] tensor flattened row-major.
@ __at *u o i na i ch i a → f { ^ ( nurl_peek_f32 o + * ch na a ) }
& `c` @ nurl_peek_f32 *u base i idx → f

// Decode the best detections above `thresh`. nc = number of classes, na =
// anchors, no = total channels (4 + nc + masks).
@ yolo_decode *u out i na i nc f thresh → ( Vec Detection ) {
    : ( Vec Detection ) dets ( vec_new [Detection] )
    : ~ i a 0
    ~ < a na {
        : ~ f best 0.0
        : ~ i bi - 0 1
        : ~ i c 0
        ~ < c nc {
            : f s ( __at out na + 4 c a )
            ? > s best { = best s = bi c } {}
            = c + c 1
        }
        ? & >= bi 0 > best thresh {
            : f cx ( __at out na 0 a )
            : f cy ( __at out na 1 a )
            : f w ( __at out na 2 a )
            : f h ( __at out na 3 a )
            ( vec_push [Detection] dets @ Detection { bi best cx cy w h a } )
        } {}
        = a + a 1
    }
    ^ dets
}

@ __iou Detection a Detection b → f {
    : f a1x - . a cx / . a w 2.0
    : f a1y - . a cy / . a h 2.0
    : f a2x + . a cx / . a w 2.0
    : f a2y + . a cy / . a h 2.0
    : f b1x - . b cx / . b w 2.0
    : f b1y - . b cy / . b h 2.0
    : f b2x + . b cx / . b w 2.0
    : f b2y + . b cy / . b h 2.0
    : f rx ? < a2x b2x a2x b2x
    : f lx ? > a1x b1x a1x b1x
    : f ry ? < a2y b2y a2y b2y
    : f ly ? > a1y b1y a1y b1y
    : f ix - rx lx
    : f iy - ry ly
    ? | < ix 0.0 < iy 0.0 { ^ 0.0 } {}
    : f inter * ix iy
    : f un - + * . a w . a h * . b w . b h inter
    ? <= un 0.0 { ^ 0.0 } { ^ / inter un }
}

// Greedy non-max suppression (per class), keeping highest-score boxes.
@ yolo_nms ( Vec Detection ) dets f iou_thresh → ( Vec Detection ) {
    : i n ( vec_len [Detection] dets )
    : ( Vec i ) used ( vec_new [i] )
    : ~ i z 0
    ~ < z n { ( vec_push [i] used 0 ) = z + z 1 }
    : ( Vec Detection ) keep ( vec_new [Detection] )
    : ~ i picked 0
    ~ < picked n {
        : ~ i best - 0 1
        : ~ f bestsc - 0.0 1.0
        : ~ i i 0
        ~ < i n {
            ?? ( vec_get [i] used i ) {
                T u → ? == u 0 { ?? ( vec_get [Detection] dets i ) { T d → ? > . d score bestsc { = bestsc . d score = best i } {} F _ → {} } } {} F _ → {}
            }
            = i + i 1
        }
        ? < best 0 { = picked n } {
            ( vec_set [i] used best 1 )
            : Detection bd ?? ( vec_get [Detection] dets best ) { T d → d F _ → @ Detection { 0 0.0 0.0 0.0 0.0 0.0 0 } }
            ( vec_push [Detection] keep bd )
            : ~ i m 0
            ~ < m n {
                ?? ( vec_get [i] used m ) {
                    T u → ? == u 0 { ?? ( vec_get [Detection] dets m ) { T dm → ? & == . dm cls . bd cls > ( __iou bd dm ) iou_thresh { ( vec_set [i] used m 1 ) } {} F _ → {} } } {} F _ → {}
                }
                = m + m 1
            }
            = picked + picked 1
        }
    }
    ( vec_free [i] used )
    ^ keep
}
