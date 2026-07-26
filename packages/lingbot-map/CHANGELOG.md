# Changelog

## 0.2.0

The port was correct and slow; this is the release where it is fast.
Measured on an RTX 4090 in f32, model load excluded on both sides, it is
**at parity with the reference**: 138 ms a frame against its 141, ahead
on the camera head (16 ms vs 54) and behind on the aggregator and depth
head. End to end, eight frames went **38.2 s -> 3.2 s** and the 4.6 GB
checkpoint load 25 s -> 1.6 s.

Almost all of the work landed in [gpukit](../gpukit) 0.6.0 and
[gpu](../gpu) 0.11.0, because every gap this hit is one any GPU package
hits — a tiled GEMM, fused attention, a caching device allocator,
per-kernel profiling. What is here:

- **The checkpoint is read straight into device memory.** The load path
  widened every f32 weight to f64, transposed the four hot Linear
  weights on the host with a column-strided write per element, and
  narrowed them again on upload. Now the mapped bytes go to the device
  as they are and the transpose is a permute kernel.
- **Two per-frame constants are built once.** The DPT
  positional-embedding grid is a pure function of (channels, height,
  width, aspect) — rebuilding it was ~10 million host `sin`/`cos` a
  frame. The DINOv2 position grid is a bicubic resample over 1024
  channels and a pure function of (gh, gw) — another 53 ms a frame.
  Together a third of the frame, both bit-identical.
- **Binary PLY by default**, `--ascii` for the text form. Formatting
  three coordinates per point cost 15 us a point — 470 ms a frame at the
  default stride, more than the depth head. The end-to-end test checks
  both formats agree.
- **`--profile`** prints per-stage frame timings and the kernel profile.
- **`--frames` and the device choice**: the run opens the strongest GPU
  on the box rather than ordinal 0, which on a machine with an old card
  beside a new one is whichever the driver enumerated first.

Numerics are unchanged or better: 18/18 against the real model, with the
aggregator at 5.291e-6 and the end-to-end depth at 1.505e-5. Everything
except the fused attention is bit-identical to the 0.1.0 kernels — the
`depthcheck` dump is byte-for-byte what a pristine 0.1.0 build produces.

## 0.1.0

First release: the Geometric Context Transformer end to end in pure
NURL — checkpoint reader, preprocessing, DINOv2 trunk, streaming
aggregator with a sliding-window KV cache, camera head, DPT depth head,
geometry, and a CLI that writes a point cloud. Every stage checked
against the reference PyTorch implementation.
