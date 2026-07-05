// image — pure-NURL image codecs. One include for the whole package:
// the Image raster, PPM (P5/P6), PNG decode + encode, and file load/save with
// format sniffing. (Baseline JPEG decode is planned as a later milestone.)
//
//     $ `deps/image/src/image.nu`
//     ?? ( image_load `photo.png` ) {
//         T im → {
//             // … use im (width/height/channels/data) …
//             ( image_save_png `out.png` im )
//             ( image_free im )
//         }
//         F _ → { ( nurl_eprintln `decode failed` ) }
//     }

$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `core.nu`
$ `ops.nu`
$ `png.nu`
$ `jpeg.nu`

// Decode by sniffing the magic bytes: PNG signature → png_decode, JPEG SOI
// (FF D8) → jpeg_decode, `P` → PPM.
@ image_decode ( Vec u ) buf → ?Image {
    : i n ( vec_len [u] buf )
    ? >= n 8 {
        ? & == ( __b buf 0 ) 137 == ( __b buf 1 ) 80 { ^ ( png_decode buf ) } {}
    } {}
    ? >= n 3 {
        ? & == ( __b buf 0 ) 255 == ( __b buf 1 ) 216 { ^ ( jpeg_decode buf ) } {}
    } {}
    ? >= n 2 {
        ? == ( __b buf 0 ) 80 { ^ ( ppm_decode buf ) } {}
    } {}
    ^ @ ?Image { F }
}

// Load and decode a file. None on an I/O error or an unrecognised/malformed
// format.
@ image_load s path → ?Image {
    : !( Vec u ) IoErr r ( read_file_bytes path )
    ?? r {
        T bytes → {
            : ?Image im ( image_decode bytes )
            ( vec_free [u] bytes )
            ^ im
        }
        F _ → { ^ @ ?Image { F } }
    }
}

@ image_save_png s path Image im → b {
    : ( Vec u ) enc ( png_encode im )
    : !v IoErr r ( write_file_bytes path enc )
    ( vec_free [u] enc )
    ?? r { T _ → { ^ T } F _ → { ^ F } }
}

@ image_save_ppm s path Image im → b {
    : ( Vec u ) enc ( ppm_encode im )
    : !v IoErr r ( write_file_bytes path enc )
    ( vec_free [u] enc )
    ?? r { T _ → { ^ T } F _ → { ^ F } }
}
