// packages/objdet/tests/detect_test.nu — self-contained CPU-logic tests.
//
// Exercises the parts that don't need the (large) detection model or a GPU:
// PPM read/write round-trip, bilinear resize, NCHW packing, the YOLOv2 grid
// decode on a synthetic grid, and non-max suppression. The end-to-end GPU
// run is covered by the demo (see README). Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/detect_test.nu /tmp/dt && /tmp/dt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/image.nu`
$ `src/detect.nu`

& `c` @ nurl_poke_f32 *u base i idx f val → v

& `c` @ nurl_peek_f32 *u base i idx → f

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ test_image → v {
    ( nurl_print `[image]\n` )
    : Image im ( img_blank 4 3 )
    ( img_set im 1 1 0 200 ) ( img_set im 1 1 1 100 ) ( img_set im 1 1 2 50 )
    ( check == ( img_get im 1 1 0 ) 200 `set/get R` )
    ( check == ( img_get im 1 1 2 ) 50 `set/get B` )
    ( check == ( img_get im 0 0 0 ) 0 `blank is black` )
    // clamp out-of-range writes
    ( img_set im 1 1 0 999 ) ( check == ( img_get im 1 1 0 ) 255 `clamp >255` )
    // resize keeps a solid colour solid
    : Image solid ( img_blank 2 2 )
    : ~ i c 0
    ~ < c 3 { ( img_set solid 0 0 c 120 ) ( img_set solid 1 0 c 120 ) ( img_set solid 0 1 c 120 ) ( img_set solid 1 1 c 120 ) = c + c 1 }
    : Image big ( img_resize solid 8 8 )
    ( check == ( img_get big 4 4 1 ) 120 `resize preserves solid colour` )
    ( check & == ( img_w big ) 8 == ( img_h big ) 8 `resize dims` )
    ( image_free im ) ( image_free solid ) ( image_free big )
}

@ test_nchw → v {
    ( nurl_print `[nchw]\n` )
    : Image im ( img_blank 2 2 )
    ( img_set im 0 0 0 10 ) ( img_set im 1 0 0 20 )
    ( img_set im 0 0 1 30 )
    : *u t ( img_to_nchw im )
    // CHW: channel 0 plane is first 4 floats; (x=1,y=0) -> index 1 = 20.
    : f r10 ( nurl_peek_f32 t 1 )
    ( check & > r10 19.5 < r10 20.5 `nchw R(1,0)=20` )
    // channel 1 plane starts at index 4; (0,0) -> index 4 = 30.
    : f g00 ( nurl_peek_f32 t 4 )
    ( check & > g00 29.5 < g00 30.5 `nchw G(0,0)=30` )
    ( nurl_free t ) ( image_free im )
}

// Build a 13x13x125 grid with one strong "dog" box planted at cell (6,6),
// anchor 0, and verify decode finds it.
@ test_decode → v {
    ( nurl_print `[decode]\n` )
    : *u grid ( nurl_alloc * 21125 4 )
    : ~ i z 0
    ~ < z 21125 { ( nurl_poke_f32 grid z # f - 0.0 10.0 ) = z + z 1 }  // all logits very negative
    : i cy 6
    : i cx 6
    : i o 0  // anchor 0, channels 0..24
    // objectness logit high; class 11 (dog) logit high
    ( nurl_poke_f32 grid + * + o 4 169 + * cy 13 cx # f 4.0 )  // to -> sigmoid ~0.98
    ( nurl_poke_f32 grid + * + o 5 169 + * cy 13 cx # f -10.0 )  // keep others low
    ( nurl_poke_f32 grid + * + + o 5 11 169 + * cy 13 cx # f 8.0 )  // class 11 = dog
    : ( Vec Detection ) dets ( yolo_decode grid 0.3 )
    ( check > ( vec_len [Detection] dets ) 0 `decode finds the planted box` )
    ?? ( vec_get [Detection] dets 0 ) {
        T d → {
            ( check == . d cls 11 `class is dog (11)` )
            ( check & > . d cx 0.4 < . d cx 0.6 `box centre near cell (6,6)` )
        } F _ → ( check F `det fetch` )
    }
    ( vec_free [Detection] dets )
    ( nurl_free grid )
}

@ test_nms → v {
    ( nurl_print `[nms]\n` )
    : ( Vec Detection ) ds ( vec_new [Detection] )
    ( vec_push [Detection] ds @ Detection { 6 0.9 0.5 0.5 0.2 0.2 } )  // dog, strong
    ( vec_push [Detection] ds @ Detection { 6 0.6 0.51 0.51 0.2 0.2 } )  // dog, overlaps -> dropped
    ( vec_push [Detection] ds @ Detection { 7 0.7 0.5 0.5 0.2 0.2 } )  // cat, same box, kept (diff class)
    : ( Vec Detection ) keep ( yolo_nms ds 0.45 )
    ( check == ( vec_len [Detection] keep ) 2 `nms drops the overlapping same-class box` )
    ( vec_free [Detection] keep )
    ( vec_free [Detection] ds )
}

@ test_names → v {
    ( nurl_print `[names]\n` )
    ( check != ( nurl_str_eq ( voc_class 11 ) `dog` ) 0 `class 11 = dog` )
    ( check != ( nurl_str_eq ( voc_class 6 ) `car` ) 0 `class 6 = car` )
}

@ main → i {
    ( test_image ) ( test_nchw ) ( test_decode ) ( test_nms ) ( test_names )
    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
