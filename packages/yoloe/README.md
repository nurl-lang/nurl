# yoloe — promptable open-vocabulary object detection, pure NURL on the GPU

A NURL port of **YOLOE** ([THU-MIG, "Real-Time Seeing Anything", ICCV
2025](https://github.com/THU-MIG/yoloe)). You *name* the classes you want —
`dog`, `bicycle`, `a person on a bike` — and the model finds them, with no
fixed label set. The detector runs on the GPU through
[`packages/onnx`](../onnx) (every layer a CUDA-C kernel compiled at runtime
via NVRTC — no external inference engine), and promptability comes from
YOLOE's **region-text contrastive head**.

> **Status: M4 done — runtime-promptable.** The full YOLOE network runs on
> the GPU in pure NURL and matches onnxruntime (M2). The detector decodes,
> NMS-es, and draws boxes (M3). And the **prompt vocabulary is now a runtime
> input** (M4): an un-fused export takes the image *and* the text embeddings
> `tpe [1,K,512]`, so you swap a small embeddings file to detect a different
> set of objects with the same model — no re-export. The promptable forward
> matches onnxruntime to ~0.02. And the **MobileCLIP text path is now pure
> NURL** (M5): the text encoder is bit-exact vs onnxruntime and the CLIP BPE
> tokenizer (`src/bpe.nu`) is byte-identical to open_clip — so prompt-words →
> embeddings needs no Python.
>
> ![dog + bicycle + truck detected](docs/demo.png)
>
> Same model, prompts supplied at runtime (`skateboard frisbee … tree wheel
> … dog bicycle`): ![runtime-prompted](docs/demo_promptable.png)

## Two ways to run

**Runtime-promptable** (`src/prompt.nu`, model from `tools/export_promptable.py`):

```
yoloe-prompt <model.onnx> <tpe.f32> <classes.txt> <image.ppm> [out.ppm]
```

`tpe.f32` is `K×512` raw MobileCLIP text features and `classes.txt` the K
prompt words — both produced by `tools/gen_tpe.py "dog,bicycle,tree,…"`.
Swap them (no re-export) to detect different objects. The model has two
inputs (`images`, `tpe`); K is fixed at export but the *meaning* of each
slot is set by the embeddings.

## Usage

```
yoloe <model.onnx> <classes.txt> <image.ppm> [out.ppm]
```

`classes.txt` is the prompt vocabulary, one class per line; the detector is
vocabulary-agnostic and infers the class count from it. The vocabulary must
match the names the model was exported with (`tools/export.py`) — swap both
the model and the class file to detect a **different** set of objects. On
the dog photo, exporting with `tree wheel window … dog bicycle` and the
matching `classes.txt` finds **dog 0.91, bicycle 0.78, tree 0.31** instead
of the truck — open-vocabulary, by changing the prompt words.

(Today the vocabulary is chosen at *export* time; M4 makes the text
embeddings a runtime input so prompts can be swapped without re-exporting.)

Images are binary PPM (P6) — `convert photo.jpg photo.ppm`. Build from the
package root:

```
nurlpkg install
NURL_STDLIB=<repo> ../../nurl.sh src/main.nu
./src/main yoloe-v8s-seg.onnx classes.txt dog.ppm dog-out.ppm
```

`example/classes.txt` holds the default vocabulary from `tools/export.py`.

## Why this is the crown jewel

The existing stack already runs real CNNs on the GPU from pure NURL:
`packages/gpu` (CUDA driver + NVRTC), `packages/onnx` (an ONNX runtime),
`packages/objdet` (tiny-yolov2, fixed 20 classes). YOLOE goes further on
every axis:

- **Open vocabulary** — detect arbitrary classes named at runtime, not a
  fixed list. This is *promptable* detection.
- **A modern architecture** — YOLOv8 backbone (C2f, SPPF), an FPN/PAN neck
  (upsample + concat), and an anchor-free DFL detection head.
- **Vision-language** — text prompts are embedded by a MobileCLIP text
  transformer; detection scores each region's visual embedding against the
  text embeddings.

## How YOLOE works (and how NURL will run it)

```
                          ┌─ box head (cv2) ── DFL ──▶ xywh boxes
image ─▶ backbone+neck ─▶─┤
        (YOLOv8, GPU)     └─ embed head (cv3) ─▶ region embeddings ─┐
                                                                    ├─▶ class logits
prompt words ─▶ MobileCLIP text encoder ─▶ text embeddings ────────┘   (region · text)
```

The **BNContrastiveHead** is the key: class logits =
`BatchNorm(region_embed) · text_embed × exp(scale) + bias` — a matmul
between per-region visual embeddings and the prompt text embeddings.
YOLOE's `fuse()` bakes the text embeddings into a 1×1 conv (zero inference
overhead → a fixed-vocab YOLOv8); keeping the head **un-fused** makes the
text embeddings a runtime input, which is how NURL gets *runtime*
promptability.

## M1 results (done)

Exported `yoloe-v8s-seg` with a 10-word prompt set and ran it through
onnxruntime on the classic dog photo — genuine open-vocabulary detection:

```
prompts: person dog cat car bicycle truck backpack bottle chair bird
  dog        0.851
  bicycle    0.744
  truck      0.458
  car        0.302
```

- Input `images [1,3,640,640]`, output `output0 [1,46,8400]` =
  `box[4] + cls[10 prompts] + mask[32]` over 8400 anchors (3 scales:
  80² + 40² + 20²). **Boxes are decoded in-graph** (DFL → xywh).
- **267 nodes, 166 initializers.** BatchNorm is folded into Conv.

### ONNX op inventory (what the runtime must cover)

| op | count | status |
|---|---|---|
| Conv | 76 | ✅ in `onnx` |
| Sigmoid | 67 | M2 (elementwise; SiLU = Sigmoid·Mul) |
| Mul | 67 | ✅ tensor⊙tensor (eltwise bmode-2) |
| Concat | 20 | M2 (channel concat) |
| Split | 10 | M2 (channel split, multi-output) |
| Add | 8 | ✅ tensor+tensor |
| Reshape | 8 | M2 (shape-tensor; alias when contiguous) |
| MaxPool | 3 | ✅ (needs explicit `pads` for SPPF 5×5) |
| Resize | 2 | M2 (nearest 2× upsample) |
| Sub / Div | 2 / 1 | M2 (box decode, broadcast) |
| Softmax | 1 | M2 (axis — DFL over 16 bins) |
| Transpose | 1 | M2 (general permute) |
| ConvTranspose | 1 | seg-mask only (skip for detection) |

## Roadmap

- **M1 — foundation** ✅ export + reference + op inventory (`tools/`).
- **M2 — op coverage** — add the ops above to `packages/onnx` plus the
  executor upgrades they need (int64 shape/anchor tensors, multi-output
  nodes, Reshape/Constant), and verify the full 267-node forward pass
  numerically against `output0`. *The core "dig onnx to diamond" work.*
- **M3 — detector** — read `output0`, threshold + NMS, map boxes back
  through the letterbox to image pixels, draw. Verify vs the reference.
- **M4 — promptability** — export the un-fused contrastive head so text
  embeddings are an input; in NURL do `BatchNorm + matmul(text_emb)`. The
  prompt-embedding bank is generated by `tools/` (MobileCLIP). The user
  passes class names at runtime.
- **M5 — diamond** ✅ — the MobileCLIP text path in pure NURL, so
  prompt-words → embeddings needs no Python.
  - **Text encoder** (done): the 12-layer, dim-512 CLIP text transformer
    (vocab 49408, 8 heads, pre-norm) runs on the GPU and is **bit-exact**
    (max abs err 0) vs onnxruntime. Exported batch=1 by
    `tools/export_text1.py` (`tokens[1,77] → feats[1,512]`); kernels added
    to `packages/onnx`: LayerNormalization, Erf/GELU, Gather (device int64
    indices), batched MatMul, N-D Transpose (perm6), and a specialised
    GatherND for the EOS readout. Verified by `tests/text_fwd.nu`.
  - **BPE tokenizer** (done): `src/bpe.nu` is a pure-NURL port of
    open_clip's `SimpleTokenizer` (the tokenizer MobileCLIP wraps as
    `get_tokenizer("ViT-B-16")`) — byte-level BPE over the 49408-entry
    encoder + 48894 merges in `assets/clip_merges.txt`, with the CLIP
    word-splitting regex, `<start_of_text>`/`<end_of_text>` framing and
    pad-to-77. Its output is **byte-identical** to open_clip across the
    COCO-80 classes and tricky cases (multi-word, digits, punctuation,
    contractions, accents, CJK) — see `tests/bpe_test.nu`. `tools/gen_tokens.nu`
    turns a `names.txt` into the `tokens.i64` the text encoder consumes;
    `tools/tokenize_cli.nu` prints ids for ad-hoc inspection.

  Pure-NURL `prompt-words → tpe` is thus two robust steps — tokenize
  (`gen_tokens.nu`) then encode (the text-encoder ONNX via the runtime,
  as in `tests/text_fwd.nu`) — no Python. `tools/gen_tpe.py` (Python
  MobileCLIP) remains as a cross-check.

## Reproducing the reference (`tools/`)

Needs a Python env with `torch` (CPU is fine), the YOLOE fork of
`ultralytics`, `mobileclip`, `onnx`, `onnxruntime`, `onnxslim`,
`onnxscript` (clone https://github.com/THU-MIG/yoloe and follow its
install; MobileCLIP weights from Apple's `mobileclip_blt.pt`).

```
python tools/export.py   <workdir>                 # YOLOE → yoloe-v8s-seg.onnx
python tools/gen_ref.py   <workdir> <image.jpg>     # letterboxed input + output0 + detections
```

`export.py` chooses the prompt vocabulary (edit `names`); `gen_ref.py`
letterboxes an image to 640×640, runs onnxruntime, and prints the
reference detections used to verify the NURL implementation.

## Requirements

- NVIDIA driver (`libcuda.so`) + NVRTC (`libnvrtc.so`) — via `onnx` → `gpu`.
- The exported model (≈45 MB) is not bundled; produce it with `tools/`.
