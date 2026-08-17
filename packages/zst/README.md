# zst

Zstandard on the command line, with no Zstandard underneath.

```sh
nurlpkg install zst
```

```
zst c FILE        compress   → FILE.zst
zst d FILE.zst    decompress → FILE
zst t FILE…       verify: structure, sizes and content checksum
zst i FILE.zst    inspect: every frame and block, and how each was coded
zst b FILE        bench: compression and decompression speed here
```

With no file (or `-`) it is a filter — `cat x | zst c | zst d | cmp - x`
works, NUL bytes and all.

The frames it writes are ordinary Zstandard frames that `unzstd` reads,
and the frames the `zstd` CLI writes are read here. Both directions are
checked against that CLI on every build of the compiler repo
(`tools/zstd_gate.sh`): 1020 reference frames — every level, with and
without checksums and content sizes, concatenated, behind skippable
frames, in 1 kB blocks and in long-distance mode — decode byte for byte,
and 1932 frames we produce pass `zstd -t` and decode back through
`zstd -d`. 600 mutated frames are refused without a crash or a hang, and
resident size stays flat across hundreds of round trips.

There is no libzstd here. The codec is
[`stdlib/std/zstd.nu`](../../stdlib/std/zstd.nu), pure NURL, so this
binary links libc and nothing else and runs where no such library
exists.

## inspect — the part no other tool gives you

`zstd --list` tells you about the frame. It cannot tell you why your file
came out the size it did, because that is decided block by block, in the
choices each block made about its literals and its three sequence
tables. Those choices are announced in bytes at the front of each
section, so they can be read out without decoding anything:

```
$ zst i nurl-stdlib.tar.zst
nurl-stdlib.tar.zst — 338.3 KiB → 1.4 MiB  (4.31x)

frame 1  window 1.4 MiB  content 1.4 MiB  checksum yes
  block  type         size       literals                   seqs   tables (ll/of/ml)
  1      compressed  33.6 KiB  huffman/4 14.5 KiB→10.3 KiB 9460  fse/fse/fse
  2      compressed  31.9 KiB  huffman/4 13.0 KiB→9.6 KiB 8943  fse/fse/fse
  3      compressed  30.0 KiB  huffman/4 8.9 KiB→6.6 KiB 8949  fse/fse/repeat
  4      compressed  27.3 KiB  huffman/4 6.8 KiB→5.1 KiB 8467  fse/fse/fse
  …
  12     compressed  11.8 KiB  treeless/4 2.2 KiB→1.7 KiB 3635  fse/fse/fse
  12 blocks, checksum 0x08385538
```

Read left to right: whether the block was compressed at all, how big it
is on disk, whether its literals were sent raw, run-length encoded, or
Huffman-coded in one or four streams — and `treeless` when the block
reused the previous block's Huffman tree instead of sending one — how
many sequences it carries, and whether each of the three sequence tables
was predefined, sent as an FSE distribution, RLE, or repeated from the
block before.

Read that run and you can watch the encoder settle: block 3 stopped
sending a match-length table and repeated the previous one, and by block
12 it was reusing the whole Huffman tree (`treeless`) because the data
had stopped changing shape. A block whose literals say `raw` on text is
one whose tree did not pay for itself; `rle` is a block that is a single
byte repeated. This is the view you want when a file compresses worse
than you expected.

It reads any Zstandard file, whoever produced it.

## Levels

`--level 1` takes the first match its hash chain offers. Every level
above it examines four candidates and considers starting one byte later,
which is worth about 4 % on text. Levels above 2 currently select the
same parameters as 2, and that is a measurement, not an omission: at 16,
48, 128 and 512 candidates the output came out 1.0 – 1.6 % **larger**,
because the extra candidates are longer matches further back, and taking
one abandons the recent offset that the following sequences would have
ridden for two bits apiece. Making depth pay needs an optimal parser,
not a bigger number. The full reasoning is in the comment above
`__zs_attempts` in `std/zstd.nu`.

Measured at level 3 against the reference at its default level 3, and
against what it can do when it stops caring about time:

| corpus | original | `zst -l 3` | `zstd -3` | `zstd -19` |
| --- | ---: | ---: | ---: | ---: |
| 100 kB dictionary text | 100 000 | **28 578** | 32 377 | 24 781 |
| 200 kB word salad | 201 306 | **60 825** | 62 111 | 55 938 |

So: ahead of the reference's default, behind what it reaches when it
brings an optimal parser. Speed is the other side of that trade — this
is one implementation of a format whose reference has had a decade of
tuning — so `zst b` prints what your machine actually does rather than a
claim:

```
$ zst b big.bin
big.bin  11 284 613 → 3 508 958 bytes  (31.0% of original, 3.21x)
  level 3   compress 32 MB/s   decompress 276 MB/s   (best of 3)
```

Decompression started at 137 MB/s and got there by profiling rather than
by guessing: the backward bit reader was a byte-at-a-time loop (37 % of
cycles) and the match copy was a byte-at-a-time loop (21 %). The first
became eight constant-shifted byte loads that LLVM folds into one
unaligned 64-bit load; the second became `memcpy` in chunks of the
offset, which never overlaps within a chunk and still reproduces the
format's run semantics. The cursor then moved out of its heap struct
into a local. libzstd is still several times faster — it decodes four
Huffman streams at once and has had a decade of tuning — and this is
what the gap costs you today.

## Safety

* `zst` never deletes an input file. The reference CLI removes the source
  unless you pass `-k`; here the safe thing is the only thing.
* An existing output file is not overwritten without `-f`.
* `d --max BYTES` refuses to produce more than that. A 100 kB frame can
  legally declare gigabytes; on input you did not produce, say so.
* A truncated frame, a flipped bit, a reserved block type and a bad
  checksum are all reported by name and exit non-zero. None of them
  decodes to plausible-looking data.

Dictionaries are not supported: a frame that names a dictionary ID is
refused (`ZstdUnsupported`) rather than decoded into something wrong.

## Licence

MIT OR Apache-2.0.
