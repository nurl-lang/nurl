# Changelog

All notable changes to `zst` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the version
scheme is [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-08-17

First release.

### Added

- `c` / `d` — compress and decompress files, or stdin to stdout when no
  file is named. Byte-clean: NUL bytes survive the pipe.
- `t` — verify a file: structure, declared sizes, and the XXH64 content
  checksum. A flipped bit, a truncated frame or a reserved block type is
  reported by name, never decoded into plausible data.
- `i` — inspect: the anatomy of every frame and block. Per block: the
  type, how the literals were coded (raw, RLE, Huffman in one or four
  streams, or a tree repeated from the previous block), the sequence
  count, and the mode of each of the three sequence tables (predefined,
  FSE, RLE, repeat). Reads any Zstandard file, whoever wrote it.
- `b` — bench: compression and decompression throughput on this machine,
  best of N.
- `--max BYTES` on decompression, because a small frame can legally
  declare a very large content size.
- Refusal to overwrite an existing output file without `-f`, and never
  deleting an input file at all.

### Notes

- Built on `stdlib/std/zstd.nu` (pure NURL, RFC 8878). No libzstd; this
  binary links libc and nothing else.
- Interoperability with the reference `zstd` CLI is checked in both
  directions by `tools/zstd_gate.sh` in the compiler repository: 1020
  reference frames decode byte-identically, and 1932 frames produced
  here pass `zstd -t` and decode back through `zstd -d`.
- Dictionaries are not supported; a frame that names a dictionary ID is
  refused rather than decoded incorrectly.
