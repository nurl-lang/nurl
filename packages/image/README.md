# image — pure-NURL image codecs

Decode and encode images with **no native library and no shell-out**. The
vision stack (objdet, yoloe) currently tells you to `convert photo.jpg
photo.ppm` before a single pixel reaches the GPU — this package closes that
loop. M1 ships PPM and a full PNG codec; baseline JPEG decode is the planned
next milestone.

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
| `( image_load path )` → `?Image` | read a file, sniff PNG/PPM, decode |
| `( image_save_png path im )` → `b` | write a lossless 8-bit PNG |
| `( image_save_ppm path im )` → `b` | write a binary PPM (P6 / P5) |
| `( image_decode buf )` → `?Image` | decode an in-memory buffer (magic-sniffed) |
| `( png_decode buf )` / `( png_encode im )` | PNG directly |
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

## Numerics / correctness

PNG is lossless, so decode and encode are **bit-exact**. The test suite proves
it against Pillow: for RGB / RGBA / greyscale / 8-bit-palette PNGs (Pillow
writes with adaptive filtering, exercising every filter), it decodes with
NURL, re-encodes to PNG and PPM, and asserts Pillow reads back exactly the
reference pixels.

## Tests

`./tests/image_test.sh` builds `tests/roundtrip.nu`, generates references with
Pillow, round-trips them, and verifies pixel-for-pixel — then re-runs the
decode/encode paths under AddressSanitizer. **8/8 pixel-exact, ASan-clean.**
Skips cleanly if Pillow isn't installed.

## Roadmap

- **M2 — baseline JPEG decode** (Huffman + dequant + IDCT + YCbCr→RGB +
  chroma upsampling), so the vision stack reads `.jpg` directly.
- Then: interlaced PNG, sub-8-bit depths, `tRNS`; wire objdet / yoloe / chart
  to load `.png`/`.jpg` and drop the `convert` step.
