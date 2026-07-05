# image — pure-NURL image codecs and raster ops

Decode, encode and transform images with **no native library and no
shell-out**. PNG (the complete still-image feature matrix), JPEG (baseline
**and progressive** decode, baseline encode), PPM — plus the raster
operations downstream code always ends up hand-rolling: resize, crop,
flips, rotations, channel conversion, drawing and alpha blit. Ships an
`img` CLI.

## Use

```nurl
$ `deps/image/src/image.nu`

?? ( image_load `photo.jpg` ) {
    T im → {
        : Image thumb ( image_resize_area im 320 200 )   // box-average shrink
        ( image_draw_rect thumb 10 10 100 80 2 4278190335 )  // red 0xFF0000FF
        ( image_save_png `thumb.png` thumb )
        ( image_free thumb )
        ( image_free im )
    }
    F _ → { ( nurl_eprintln ( image_error ) ) }   // says WHY it failed
}
```

`Image` is `{ i width, i height, i channels, ( Vec u ) data }` — 8 bits per
channel, row-major, tightly packed. Channels: 1 grey, 2 grey+alpha, 3 RGB,
4 RGBA. `image_get`/`image_set` are bounds-checked (out-of-range reads 0,
writes are ignored). Transform functions return a **new** image — free
both.

## CLI

`nurlpkg install image` gives you `img`:

```
img info photo.jpg                    # 4032x3024 RGB
img convert scan.png scan.jpg -q 85   # format from the extension
img resize photo.jpg web.jpg 800x     # keep aspect; 800x600 / x600 also work
```

Shrinking box-averages (clean thumbnails), growing is bilinear. Extensions:
`.png` `.jpg` `.jpeg` `.ppm` `.pgm`.

## API

### Files and buffers

| Call | |
| --- | --- |
| `( image_load path )` → `?Image` | read a file, sniff PNG/JPEG/PPM, decode |
| `( image_decode buf )` → `?Image` | same, from an in-memory `( Vec u )` |
| `( image_error )` → `s` | why the last decode returned None (static string) |
| `( image_save_png path im )` → `b` | lossless 8-bit PNG |
| `( image_save_jpeg path im quality )` → `b` | baseline JPEG, quality 1–100 |
| `( image_save_ppm path im )` → `b` | binary PPM (P6 / P5) |
| `( png_decode buf )` / `( png_encode im )` | PNG directly |
| `( jpeg_decode buf )` → `?Image` | baseline + progressive JPEG |
| `( jpeg_encode im q )` → `( Vec u )` | 4:2:0 below q90, 4:4:4 from q90 |
| `( jpeg_encode_sub im q sub )` → `( Vec u )` | force 0=4:4:4 / 1=4:2:2 / 2=4:2:0 |
| `( ppm_decode buf )` / `( ppm_encode im )` | PPM directly |

### Raster

| Call | |
| --- | --- |
| `( image_new w h ch )` / `( image_of w h ch data )` / `( image_free im )` | |
| `( image_width im )` `( image_height im )` `( image_channels im )` | |
| `( image_get im x y c )` / `( image_set im x y c v )` | per channel |
| `( image_get_rgba im x y )` / `( image_set_rgba im x y rgba )` | packed `0xRRGGBBAA`, channel-mapped |
| `( image_clone im )` | deep copy |

### Ops (`ops.nu`, included by `image.nu`)

| Call | |
| --- | --- |
| `( image_resize im w h )` | bilinear, edge-clamped — upscale & mild shrink |
| `( image_resize_area im w h )` | box average — thumbnails, exact for integer factors |
| `( image_resize_nearest im w h )` | blocky, exact |
| `( image_crop im x y w h )` | clipped window copy |
| `( image_flip_h im )` / `( image_flip_v im )` | |
| `( image_rot90 im )` / `( image_rot180 im )` / `( image_rot270 im )` | clockwise |
| `( image_convert im ch )` | 1/2/3/4 channels; grey↔RGB via BT.601 luma |
| `( image_fill im rgba )` / `( image_fill_rect im x0 y0 x1 y1 rgba )` | in place, clipped |
| `( image_draw_rect im x0 y0 x1 y1 t rgba )` | outline, `t` px thick, inward |
| `( image_draw_line im x0 y0 x1 y1 rgba )` | Bresenham, clipped |
| `( image_blit dst src dx dy )` | clipped; source-over blend when src has alpha |

Colours are one packed int, `0xRRGGBBAA` — e.g. opaque red `4278190335`
(0xFF0000FF). Grey targets take the BT.601 luma; targets without alpha drop
A. Drawing overwrites; only `image_blit` blends.

## Format support

**PNG decode** — the full still-image matrix: bit depths 1/2/4/8/16 (deep
samples scaled to 8-bit), all colour types (grey, RGB, palette→RGB,
grey+alpha, RGBA), **Adam7 interlacing**, **tRNS** (palette alpha; grey/RGB
colour keys add an alpha channel), all five scanline filters. Encode:
8-bit, non-interlaced, filter 0 — lossless round-trip.

**JPEG decode** — 8-bit Huffman, greyscale or YCbCr, any 4:4:4 / 4:2:2 /
4:2:0 / 4:1:1 subsampling, restart intervals, sequential (SOF0/SOF1) and
**progressive** (SOF2: spectral selection + successive approximation, the
format most web JPEGs use). Chroma upsampling is libjpeg's default "fancy"
(triangular) filter, bit-matching jdsample.c for 2x1/2x2 expansion, so
decode matches libjpeg/Pillow to within IDCT rounding even at 4:2:0;
progressive output is bit-identical to the baseline decode of the same
content. **Encode** — baseline JFIF, Annex K
tables, libjpeg-style quality 1–100, 4:4:4 / 4:2:2 / 4:2:0; loss profile
matches Pillow's encoder on the same content.

Not supported (clean `None` + `image_error` reason, never an out-of-bounds
read): JPEG arithmetic coding, 12-bit, lossless/hierarchical, CMYK/YCCK;
images beyond 64 Mpx (JPEG) / 256 Mpx (PNG/PPM).

## Hardening

`tests/fuzz.nu` drives every decoder through deterministic truncation,
point-mutation and LCG sweeps — 10k+ mutants per seed across six seed
formats — under AddressSanitizer + LeakSanitizer with a hang timeout.
Malformed input gets a clean `None`; JPEG SOF sanity (sampling factors,
dimension caps) and a PNG preflight (pixel data must actually be present
before the output raster is allocated) keep hostile files from costing
gigabytes.

## Tests

`./tests/image_test.sh` — deterministic ops checks (no references needed),
then against Pillow: PNG/PPM round-trips pixel-exact, a 16-case
hand-crafted PNG feature matrix (Pillow can't even write most of them)
pixel-exact, JPEG decode within tolerance (baseline + progressive), JPEG
encode re-decoded by Pillow, CLI smoke tests, the fuzz sweeps, and an ASan
pass over everything. Skips the reference parts cleanly without Pillow.

## Consumers

[`objdet`](../objdet) and [`yoloe`](../yoloe) decode photos and encode
annotated output through this package (their private PPM/resize/draw
copies are gone); [`chart`](../chart) is terminal-only and needs no raster.

## Roadmap

- Optional PNG adaptive filtering for smaller encodes; fancier resampling
  (Lanczos) if a consumer needs it.
