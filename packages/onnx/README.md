# onnx — run ONNX models from pure NURL, on the GPU

Load a trained [ONNX](https://onnx.ai) model and run inference on the GPU —
written entirely in NURL. The model's protobuf is decoded by a pure-NURL
wire-format reader (no `protoc`, no protobuf library); inference runs on
the GPU through the [`gpu`](../gpu) package, with each operator a CUDA-C
kernel compiled to PTX at runtime (NVRTC) and every weight and activation
resident on the device.

**v0.1.0 is a proof-of-concept** for feed-forward MLPs: it supports the
`Gemm` and `Relu` operators and matches onnxruntime's output.

```
onnx <model.onnx> <input.f32> [expected.f32]
```

```
$ onnx tests/data/tiny.onnx tests/data/tiny.in.f32 tests/data/tiny.out.f32
device: NVIDIA GeForce RTX 4090
input elements: 4
output [3]: 0.0641051 0.0813513 -0.0214344
max abs error vs reference: 0
MATCH ✓
```

A 784→128→10 MLP (MNIST-shaped) matches the onnxruntime reference to within
`1.8e-6` (float32 rounding).

## How it works

```
model.onnx ──pb.nu──▶ ONNX graph ──runtime.nu──▶ GPU execution ──▶ output
            (protobuf            (value map,        (ops.nu kernels
             wire decode)         node order)        via gpu.nu/NVRTC)
```

- **`src/pb.nu`** — a minimal protobuf wire decoder (varints, the four wire
  types, length-delimited sub-messages, packed repeated). Pure NURL over a
  `Vec u` byte buffer.
- **`src/model.nu`** — the ONNX schema on top of `pb.nu`: `ModelProto →
  GraphProto → { NodeProto[], TensorProto initializers, I/O names }`,
  `AttributeProto`, and `TensorProto.raw_data` (little-endian f32) read
  straight into a host buffer.
- **`src/ops.nu`** — operators as CUDA-C kernels (`Gemm`, `Relu`), compiled
  once via NVRTC and launched over `gpu.nu`.
- **`src/runtime.nu`** — the executor: uploads weights + input once, walks
  the graph in node order keeping activations on the GPU, downloads the
  named output.

The CUDA dependency lives **entirely in the `gpu` package** — a GPU-less
host never pulls it in. This package only knows the neutral
`gpu_open / gpu_compile / gpu_alloc / gpu_upload / gpu_launch / …` surface.

## Operators

| op | notes |
|---|---|
| `Gemm` | `Y = α·A·B(ᵀ) + β·C`, bias `C` broadcast; `alpha`/`beta`/`transA`/`transB` |
| `Relu` / `LeakyRelu` | elementwise; `LeakyRelu` honours `alpha` |
| `Conv` | NCHW, 2-D, `group=1`; `auto_pad` (SAME_UPPER/LOWER) or explicit `pads`, `strides`, optional bias |
| `MaxPool` | NCHW, 2-D; `kernel_shape`, `strides`, `auto_pad` or explicit `pads` (−∞ padding) |
| `BatchNormalization` | inference form, per channel, `epsilon` |
| `Mul` / `Add` / `Sub` / `Div` | broadcast operand (scalar, per-channel, per-inner, or full); Mul/Add either order |
| `Sigmoid` | elementwise (SiLU = `Sigmoid`·`Mul`) |
| `Concat` / `Split` | along any axis; Split aliases contiguous slices, multi-output |
| `Reshape` / `Transpose` | reinterpret (alias) / general N-D permute |
| `Resize` | nearest-neighbour integer upscale (`scales`) |
| `Softmax` | along any axis |

Initializers may be `FLOAT` (GPU weights) or `INT64` (host-side shape /
size / anchor tensors). The op set is enough to run a full **YOLOv8 /
YOLOE** backbone, neck, and anchor-free DFL detection head — verified
end-to-end against onnxruntime (see `packages/yoloe`).

Tensors are float32, N-D (dense 2-D and NCHW 4-D). Enough to run a
multi-layer perceptron **and a tiny-YOLO-class CNN detector** end-to-end —
the full tiny-yolov2 forward pass matches onnxruntime to ~2e-5. Grouped/
dilated convolutions, softmax, concat/reshape/transpose, and dynamic shapes
are future work; the executor and kernel dispatch are built to extend.

The `packages/onnx` tensor + op layer is consumed by
[`packages/objdet`](../objdet), which adds image I/O, YOLO decoding, and NMS
for real object detection.

## Building & running

This package depends on `gpu`. From the package root:

```
nurlpkg install                 # symlinks deps/gpu (path dep) or fetches gpu 0.1.0
NURL_STDLIB=<repo> ../../nurl.sh src/main.nu
./src/main tests/data/tiny.onnx tests/data/tiny.in.f32 tests/data/tiny.out.f32
```

Or install from the registry: `nurlpkg install onnx`.

## Test fixtures

`tests/data/` holds a tiny 4→8→3 MLP (`tiny.onnx`) plus a reference input
and onnxruntime output. `tests/data/gen_model.py` regenerates them (and a
larger MNIST-shaped model) with `onnx` + `onnxruntime`. `tests/infer_test.nu`
asserts the parse structure (always) and the GPU result against the
reference (skipping cleanly when no GPU is present).

## Requirements

- NVIDIA driver (`libcuda.so`) and NVRTC (`libnvrtc.so`, CUDA toolkit) —
  via the `gpu` dependency.
- An ONNX model using only the supported operators, float32 tensors,
  weights in `raw_data`.
