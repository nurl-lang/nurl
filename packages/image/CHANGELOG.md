# Changelog

## 0.4.0

- **libjpeg-exact "fancy" chroma upsampling** — 2x1/2x2 expansion now uses
  libjpeg's default triangular filter (bit-matching jdsample.c, including
  the 1/2 and 8/7 rounding biases and edge clamping); other ratios keep box,
  as libjpeg does. 4:2:0 decode drops to IDCT-rounding distance from Pillow
  (synthetic max_diff 3, tolerance tightened 12 → 4; real photos max 3,
  mean ≈ 0.02). Both baseline and progressive decode benefit.
- **Consumers wired**: objdet 0.3.0 and yoloe 0.5.0 now decode/encode
  through this package (their private PPM/resize/draw copies are deleted) —
  both proven equivalent bit-for-bit on their preprocessing tensors, and
  yoloe verified live on GPU reading a JPEG and writing a mask-overlay PNG.

## 0.3.0

The "diamond" release: real-world coverage on every axis.

- **Progressive JPEG decode** (SOF2) — spectral selection + successive
  approximation, DC/AC first+refinement scans, EOB runs, restart intervals,
  interleaved and single-component scans. Bit-identical to the baseline
  decode of the same content; SOF1 (extended sequential) also accepted.
- **Baseline JPEG encode** — `jpeg_encode` / `jpeg_encode_sub` /
  `image_save_jpeg`: quality 1–100 (libjpeg-style scaling), 4:4:4 / 4:2:2 /
  4:2:0, Annex K quantisation + Huffman tables, JFIF headers. Loss profile
  matches Pillow's encoder.
- **Complete PNG decode** — bit depths 1/2/4/8/16, Adam7 interlacing, tRNS
  (palette alpha + grey/RGB colour keys → alpha channel), verified
  pixel-exact against a 16-case hand-crafted feature matrix.
- **Raster ops** (`ops.nu`) — `image_resize` (bilinear) /
  `image_resize_area` (box) / `image_resize_nearest`, crop, flips,
  rotations, `image_convert` (1/2/3/4 ch, BT.601), fill / rect / line
  drawing, alpha blit, packed `0xRRGGBBAA` pixel access. `image_get`/`set`
  are now bounds-checked (a write at x==width used to wrap to the next row).
- **`img` CLI** — `info` / `convert` / `resize` (keep-aspect `800x`/`x600`),
  `-q` quality, formats by extension.
- **`image_error`** — stb-style failure reason for every `None`.
- **Hardening** — deterministic fuzz harness (truncation / point / LCG
  sweeps, ASan+LSan, hang timeouts). Fixed a real infinite loop: baseline
  block decode never checked the Huffman decoder's corrupt-table return, so
  one flipped DHT byte spun forever. JPEG SOF now validates sampling
  factors and caps dimensions at 64 Mpx; PNG preflights inflated size
  before allocating the output raster; PPM caps dimensions.

## 0.2.0

- **Baseline JPEG decode** (`jpeg_decode`) — sequential-DCT Huffman JPEGs:
  8-bit greyscale or YCbCr, any 4:4:4 / 4:2:2 / 4:2:0 / 4:1:1 subsampling, and
  restart intervals. Full segment parser (DQT / DHT / SOF0 / DRI / SOS), a
  separable float IDCT, box chroma upsampling, and YCbCr→RGB. Matches Pillow
  (libjpeg) to within IDCT/upsampling rounding. `image_load` / `image_decode`
  sniff the JPEG SOI marker. Progressive / arithmetic / 12-bit / 4-component
  return a clean `None`.

## 0.1.0

- Initial release: the `Image` raster, PPM (P5/P6), and a full PNG codec
  (decode of 8-bit greyscale / RGB / palette / grey+alpha / RGBA with all five
  scanline filters; lossless 8-bit encode), plus `image_load` /
  `image_save_png` / `image_save_ppm`.
