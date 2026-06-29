// packages/objdet/src/detect.nu — tiny-YOLOv2 detection head.
//
// Decodes the [1,125,13,13] grid the network produces into boxes: each of
// the 13×13 cells predicts 5 anchor boxes, each carrying (tx,ty,tw,th,to)
// + 20 VOC class logits. Box centre/size come from the cell + anchor with
// sigmoid/exp; the score is objectness × softmax(class). Overlapping boxes
// of the same class are then removed by non-max suppression.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

// A detection in normalised (0..1) centre/size coordinates.
: Detection { i cls  f score  f cx  f cy  f w  f h }

@ sigmoid f x → f { ^ / 1.0 + 1.0 ( exp - 0.0 x ) }

// VOC 2007 20 classes (tiny-yolov2 order).
@ voc_class i i → s {
    ?? ( vec_get [String] ( __voc ) i ) { T s → ^ ( string_data s ) F _ → ^ `?` }
}
@ __voc → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `aeroplane` ) ) ( vec_push [String] v ( string_from `bicycle` ) )
    ( vec_push [String] v ( string_from `bird` ) ) ( vec_push [String] v ( string_from `boat` ) )
    ( vec_push [String] v ( string_from `bottle` ) ) ( vec_push [String] v ( string_from `bus` ) )
    ( vec_push [String] v ( string_from `car` ) ) ( vec_push [String] v ( string_from `cat` ) )
    ( vec_push [String] v ( string_from `chair` ) ) ( vec_push [String] v ( string_from `cow` ) )
    ( vec_push [String] v ( string_from `diningtable` ) ) ( vec_push [String] v ( string_from `dog` ) )
    ( vec_push [String] v ( string_from `horse` ) ) ( vec_push [String] v ( string_from `motorbike` ) )
    ( vec_push [String] v ( string_from `person` ) ) ( vec_push [String] v ( string_from `pottedplant` ) )
    ( vec_push [String] v ( string_from `sheep` ) ) ( vec_push [String] v ( string_from `sofa` ) )
    ( vec_push [String] v ( string_from `train` ) ) ( vec_push [String] v ( string_from `tvmonitor` ) )
    ^ v
}

// Anchor box dims (w,h in grid cells), tiny-yolov2 VOC.
@ __anchor i b i which → f {
    : ( Vec f ) a ( vec_new [f] )
    ( vec_push [f] a 1.08 ) ( vec_push [f] a 1.19 ) ( vec_push [f] a 3.42 ) ( vec_push [f] a 4.41 )
    ( vec_push [f] a 6.63 ) ( vec_push [f] a 11.38 ) ( vec_push [f] a 9.42 ) ( vec_push [f] a 5.11 )
    ( vec_push [f] a 16.62 ) ( vec_push [f] a 10.52 )
    : f r ?? ( vec_get [f] a + * b 2 which ) { T x → x F _ → 1.0 }
    ( vec_free [f] a ) ^ r
}

// grid value at (channel, cy, cx) for a 13×13 grid.
@ __gv *u grid i ch i cy i cx → f { ^ ( nurl_peek_f32 grid + * ch 169 + * cy 13 cx ) }

// Decode the grid into detections above `thresh`.
@ yolo_decode *u grid f thresh → ( Vec Detection ) {
    : ( Vec Detection ) out ( vec_new [Detection] )
    : ~ i cy 0
    ~ < cy 13 {
        : ~ i cx 0
        ~ < cx 13 {
            : ~ i b 0
            ~ < b 5 {
                : i o * b 25
                : f tx ( __gv grid o cy cx )
                : f ty ( __gv grid + o 1 cy cx )
                : f tw ( __gv grid + o 2 cy cx )
                : f th ( __gv grid + o 3 cy cx )
                : f to ( __gv grid + o 4 cy cx )
                : f conf ( sigmoid to )
                // softmax over the 20 class logits → best class + prob
                : ~ f mx ( __gv grid + o 5 cy cx )
                : ~ i k 1
                ~ < k 20 { : f cval ( __gv grid + + o 5 k cy cx ) ? > cval mx { = mx cval } {} = k + k 1 }
                : ~ f sum 0.0
                : ~ i bi 0
                : ~ f bp 0.0
                : ~ i j 0
                ~ < j 20 {
                    : f e ( exp - ( __gv grid + + o 5 j cy cx ) mx )
                    = sum + sum e
                    ? > e bp { = bp e = bi j } {}
                    = j + j 1
                }
                : f pbest / bp sum
                : f score * conf pbest
                ? > score thresh {
                    : f x / + # f cx ( sigmoid tx ) 13.0
                    : f y / + # f cy ( sigmoid ty ) 13.0
                    : f w / * ( __anchor b 0 ) ( exp tw ) 13.0
                    : f h / * ( __anchor b 1 ) ( exp th ) 13.0
                    ( vec_push [Detection] out @ Detection { bi score x y w h } )
                } {}
                = b + b 1
            }
            = cx + cx 1
        }
        = cy + cy 1
    }
    ^ out
}

// IoU of two detections (centre/size form).
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

// Non-max suppression: sort by score, greedily keep, drop same-class
// boxes overlapping a kept box by more than `iou_thresh`.
@ yolo_nms ( Vec Detection ) dets f iou_thresh → ( Vec Detection ) {
    : i n ( vec_len [Detection] dets )
    // selection sort indices by score desc into `order`
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
                T u → ? == u 0 {
                    ?? ( vec_get [Detection] dets i ) { T d → ? > . d score bestsc { = bestsc . d score = best i } {} F _ → {} }
                } {} F _ → {}
            }
            = i + i 1
        }
        ? < best 0 { = picked n } {
            ( vec_set [i] used best 1 )
            : Detection bd ?? ( vec_get [Detection] dets best ) { T d → d F _ → @ Detection { 0 0.0 0.0 0.0 0.0 0.0 } }
            ( vec_push [Detection] keep bd )
            // suppress remaining same-class overlaps
            : ~ i m 0
            ~ < m n {
                ?? ( vec_get [i] used m ) {
                    T u → ? == u 0 {
                        ?? ( vec_get [Detection] dets m ) {
                            T dm → ? & == . dm cls . bd cls > ( __iou bd dm ) iou_thresh { ( vec_set [i] used m 1 ) } {} F _ → {}
                        }
                    } {} F _ → {}
                }
                = m + m 1
            }
            = picked + picked 1
        }
    }
    ( vec_free [i] used )
    ^ keep
}
