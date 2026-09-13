# Changelog

## 0.9.0

The package's own protobuf decoder is gone. `stdlib/ext/protobuf.nu` — the
checked codec promoted into the standard library in toolchain 0.64.0 — now
owns the wire format, and `src/pb.nu` is the seam onto it.

The old decoder read a model on trust. Nothing bounded a length prefix, a
varint could shift past 64 bits, and `pb_skip` knew four wire types out of
six: a group tag advanced the cursor by nothing at all. So a malformed
model was not rejected, it was *decoded anyway* — and sometimes not even
that. Over 700 mutations of real models, the old reader silently returned a
graph for 454 of them and **hung forever on 3**, where a corrupt length
prefix drove the cursor past the buffer and the end-of-message test never
came true again. `tests/data/malformed_length.onnx` is one of those three,
kept as a regression: 544 bytes, and it used to spin.

What the parser does with a bad model is now a decision, not an accident:

- **`onnx_parse_checked`** returns the first wire-format error with its
  code and byte offset — `bad-length offset=15` for the fixture above.
- **`onnx_parse`** keeps its old signature and its old contract for the
  six packages that call it: a malformed model yields an empty graph,
  which runs no nodes.

A `PReader` is a checked stdlib reader plus a sticky error. Every read is
infallible where it is called and returns a neutral value once the reader
has failed, so each message parser stays the flat `while more { ... }` loop
it already was — the first failure latches, the loop stops, and a
sub-message carries its failure back to its parent.

`TensorProto.raw_data` is **borrowed in place** now. The old code recorded
the block's offset, let the cursor run on, then rewound to re-read it; the
stdlib reader hands back a slice of the model buffer, so the weights are
decoded straight out of it and the cursor never moves backwards.

Verified against the parser it replaces: **1,918 ONNX models** — the whole
`onnx` backend test corpus plus this package's own fixture — parsed with
both implementations and dumped in full (every node, attribute,
initializer, and a position-sensitive checksum over every weight block).
All 1,918 dumps are **byte-identical**. The dump tool is committed as
`tests/parse_dump.nu`; it needs no GPU. 500 further runs under
ASan/UBSan/LeakSanitizer — 200 real models and 300 mutations — report
nothing.

`nurl-version = "0.64.0"` is now declared: that is the toolchain that first
shipped `stdlib/ext/protobuf.nu`.

### Changed

- `pb_read_f32_into` / `pb_read_i64_into` over a `*PbR` cursor become
  `slice_f32_into` / `slice_i64_into` over a `( Slice u )`, with
  `vec_f32_into` / `vec_i64_into` for a whole byte vector — which is what
  reading a plain little-endian `.f32` file always was. `PbR`, `pb_sub`,
  `pb_pos`, `pb_set_pos`, `pb_blob_start`, `pb_byte`, `pb_field`,
  `pb_wire` and `pb_free` are gone; `packages/yoloe` is updated with them.
- `pb_skip` takes the `ProtoTag` that was just read instead of a bare wire
  number, and handles groups.

## 0.8.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `tensor` `^0.4` → `^0`
- `gpukit` `^0.6` → `^0`
- `gpu` `^0.11` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name. That was not hypothetical here: a registry install
resolved `gpukit` to a 0.6 series while the monorepo builds this package
against 0.7 — two different builds of the same commit.

No source change.

## 0.8.0

Everything a torch U²-Net export needs — proven on skyseg.onnx
(map-anything's --mask-sky), max 1.1e-6 against onnxruntime:

- **Host-side INT64 shape folding.** The Shape → Gather/Unsqueeze/
  Concat/Cast/Slice chains a torch export leaves behind now execute on
  the host (they are constants once the input shape is known); a
  host-int tensor lives in the ordinary value map under an RT_HOSTI
  sentinel. Device Gather/Concat/Slice are untouched — the host path
  only claims a node whose data is host-side.
- **Constant nodes.** The embedded TensorProto payload is parsed
  (INT64 values folded into the attribute's ints) instead of warping
  through "unsupported op".
- **Resize: `sizes` input + linear mode.** An explicit sizes input
  (opset ≥ 11, fed by the host chains) wins over float scales, and
  mode=linear runs half-pixel bilinear (pytorch_half_pixel agrees with
  half_pixel at every output size above 1). Nearest + scales behave as
  before.
- **Conv dilations** via gpukit 0.6.3's gkd_conv2d_dil — ignoring the
  attribute silently GREW every dilated map (pad 2, effective kernel
  read as 3) and the failure surfaced three stages later as Concat
  size mismatches.
- **MaxPool ceil_mode** rounds the output size up (U²-Net's 5→3).
- Concat's failure diagnostic now names the node, the input and both
  element counts.
- `gate_dump imgf` — run a model on a real f32 input from a file, for
  oracle comparisons.

## 0.7.3 and earlier

See git history (the package predates this changelog).
