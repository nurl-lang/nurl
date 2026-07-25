#!/usr/bin/env python3
"""Generate .pt fixtures and the expected-value oracle for torchpt's tests.

Writes into the directory given as argv[1]:
  <dir>/*.pt        the checkpoints
  <dir>/oracle.txt  "<file> <tensor> <dtype> <shape> <values…>" per tensor,
                    values as repr-stable decimal, produced by torch.load

Every fixture is deliberately awkward in a different way: protocol
versions 2 through 5, nested and non-string-keyed dicts, tensors sharing
one storage, non-contiguous views, zero-element tensors, and every dtype
torch can put in a storage.
"""
import os
import sys

import torch


def dtype_tag(t):
    return {
        torch.float64: "f64", torch.float32: "f32", torch.float16: "f16",
        torch.bfloat16: "bf16", torch.int64: "i64", torch.int32: "i32",
        torch.int16: "i16", torch.int8: "i8", torch.uint8: "u8",
        torch.bool: "bool",
    }[t]


def build():
    g = torch.Generator().manual_seed(20260725)
    fixtures = {}

    # 1. every dtype, protocol 2 (torch's default)
    every = {}
    for t in (torch.float64, torch.float32, torch.float16, torch.bfloat16,
              torch.int64, torch.int32, torch.int16, torch.int8, torch.uint8):
        if t.is_floating_point:
            every[f"x.{dtype_tag(t)}"] = (torch.rand(3, 4, generator=g) * 20 - 10).to(t)
        else:
            every[f"x.{dtype_tag(t)}"] = torch.randint(-8, 8, (3, 4), generator=g).to(t)
    every["x.bool"] = torch.tensor([True, False, True, True])
    every["x.scalar"] = torch.tensor(3.25)
    every["x.empty"] = torch.zeros(0, dtype=torch.float32)
    fixtures["every_dtype.pt"] = (every, 2)

    # 2. a nested training-checkpoint shape, protocol 2
    nested = {
        "model": {
            "blocks.0.attn.qkv.weight": torch.randn(6, 4, generator=g),
            "blocks.0.attn.qkv.bias": torch.randn(6, generator=g),
            "blocks.1.mlp.fc1.weight": torch.randn(8, 4, generator=g),
        },
        "optimizer": {"state": {}, "lr": 0.0003},
        "epoch": 7,
        "note": "a string value, not a tensor",
        "flags": [True, False, None],
        "shapes": (3, 4, 5),
    }
    fixtures["nested.pt"] = (nested, 2)

    # 3. shared storage + non-contiguous views, protocol 2
    base = torch.arange(24, dtype=torch.float32).reshape(4, 6)
    shared = {
        "base": base,
        "row_slice": base[1:3],          # contiguous view, nonzero offset
        "col_slice": base[:, 2:4],       # NON-contiguous view
        "transposed": base.t(),          # NON-contiguous view
        "same_object": base,             # the identical tensor twice
    }
    fixtures["views.pt"] = (shared, 2)

    # 4. the same payload at protocols 3, 4 and 5 — protocol 4+ switches
    #    to FRAME / SHORT_BINUNICODE / MEMOIZE / STACK_GLOBAL opcodes
    proto_payload = {
        "w": torch.randn(5, 3, generator=g),
        "b": torch.randn(5, generator=g),
        "meta": {"n": 5, "scale": 0.125, "ok": True},
    }
    for proto in (3, 4, 5):
        fixtures[f"proto{proto}.pt"] = (proto_payload, proto)

    return fixtures


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    lines = []
    for fname, (obj, proto) in build().items():
        path = os.path.join(out, fname)
        torch.save(obj, path, pickle_protocol=proto, _use_new_zipfile_serialization=True)
        loaded = torch.load(path, weights_only=False)
        for name, t in walk(loaded, ""):
            vals = t.flatten().to(torch.float64).tolist()
            lines.append("%s %s %s %s %s" % (
                fname, name, dtype_tag(t.dtype),
                "x".join(str(d) for d in t.shape) if t.dim() else "scalar",
                " ".join(fmt(v) for v in vals)))
    with open(os.path.join(out, "oracle.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("fixtures: %d, oracle rows: %d" % (len(build()), len(lines)))


def fmt(v):
    if v == int(v) and abs(v) < 1e15:
        return str(int(v))
    return repr(v)


def walk(obj, prefix):
    if torch.is_tensor(obj):
        yield prefix, obj
        return
    if isinstance(obj, dict):
        for k, v in obj.items():
            if not isinstance(k, str):
                continue
            yield from walk(v, k if not prefix else prefix + "." + k)
        return
    if isinstance(obj, (list, tuple)):
        for i, v in enumerate(obj):
            yield from walk(v, str(i) if not prefix else prefix + "." + str(i))


if __name__ == "__main__":
    main()
