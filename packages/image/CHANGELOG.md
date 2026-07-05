# Changelog

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
