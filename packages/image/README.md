# image — pure-NURL image codecs

Decode and encode images with **no native library and no shell-out**. The
vision stack (objdet, yoloe) used to tell you to `convert photo.jpg photo.ppm`
before a single pixel reached the GPU — this package closes that loop. It
decodes PNG, **baseline JPEG**, and PPM, and encodes PNG and PPM.

## Use

```nurl
$ `deps/image/src/image.nu`

?? ( image_load `photo.png` ) {
    T im → {
        // im: width / height / channels (1 grey, 3 RGB, 4 RGBA) + a packed
        // row-major byte buffer. Read pixels with image_get, write out with
        // image_save_png / image_save_ppm.
        ( image_save_ppm `photo.ppm` im )
        ( image_free im )
    }
    F _ → { ( nurl_eprintln `decode failed` ) }
}
```

## API

| Call | |
| --- | --- |
| `( image_load path )` → `?Image` | read a file, sniff PNG/JPEG/PPM, decode |
| `( image_save_png path im )` → `b` | write a lossless 8-bit PNG |
| `( image_save_ppm path im )` → `b` | write a binary PPM (P6 / P5) |
| `( image_decode buf )` → `?Image` | decode an in-memory buffer (magic-sniffed) |
| `( png_decode buf )` / `( png_encode im )` | PNG directly |
| `( jpeg_decode buf )` → `?Image` | baseline JPEG directly |
| `( ppm_decode buf )` / `( ppm_encode im )` | PPM directly |
| `( image_new w h ch )`, `( image_of w h ch data )`, `( image_free im )` | |
| `( image_width/height/channels im )`, `( image_get im x y c )`, `( image_set im x y c v )` | |

`Image` is `{ i width, i height, i channels, ( Vec u ) data }` — 8 bits per
channel, row-major, tightly packed.

## PNG support

- **Decode**: 8-bit depth, non-interlaced — greyscale, RGB, palette (expanded
  to RGB), grey+alpha, and RGBA. All five scanline filters (None / Sub / Up /
  Average / Paeth) are reconstructed. Built on the stdlib `deflate` codec (the
  zlib header is stripped; `inflate` stops at the final block).
- **Encode**: 8-bit, non-interlaced, filter 0; the colour type follows the
  image's channel count. Lossless — `decode → encode → decode` reproduces the
  pixels exactly.
- **Not yet** (clean `None`, never an out-of-bounds read): interlaced (Adam7),
  bit depths other than 8, and `tRNS` transparency on palette/grey images.

## JPEG support

- **Decode** (baseline / sequential DCT, Huffman): 8-bit, greyscale or YCbCr,
  any 4:4:4 / 4:2:2 / 4:2:0 / 4:1:1 subsampling, and restart intervals. Full
  segment parser (DQT / DHT / SOF0 / DRI / SOS), a separable float IDCT, box
  chroma upsampling, and YCbCr→RGB.
- **Not yet** (clean `None`): progressive, arithmetic coding, 12-bit, and
  4-component (CMYK/YCCK).

## Numerics / correctness

PNG is lossless, so its decode and encode are **bit-exact**. JPEG is lossy and
the spec permits IDCT variation, so decode matches a reference decoder
(libjpeg, via Pillow) to within IDCT and chroma-upsampling rounding — not
bit-exact, but close: on smooth content the max per-channel difference is a
couple of counts for 4:4:4/greyscale (IDCT only) and single digits for 4:2:0
(box vs Pillow's "fancy" upsampling).

## Tests

`./tests/image_test.sh` builds `tests/roundtrip.nu` and checks against Pillow:
PNG/PPM decode→encode is asserted **pixel-exact** (Pillow's adaptive filtering
exercises every PNG filter), and baseline-JPEG decode (4:4:4 / 4:2:0 /
greyscale) is asserted **within tolerance** of Pillow's own decode. Then it
re-runs every decode/encode path under AddressSanitizer. Latest run: PNG
pixel-exact; JPEG max-diff 2 / 6 / 1; **ASan-clean**. Skips cleanly without
Pillow.

## Roadmap

- Interlaced (Adam7) PNG, sub-8-bit depths, `tRNS`; "fancy" (triangle) chroma
  upsampling for closer JPEG parity.
- Wire objdet / yoloe / chart to `image_load` `.png`/`.jpg` directly and delete
  the `convert` step.
