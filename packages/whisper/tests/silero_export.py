#!/usr/bin/env python3
# tests/silero_export.py — vad/silero_vad_v5.safetensors from Silero's ONNX file.
#
#   python3 tests/silero_export.py silero_vad.onnx vad/silero_vad_v5.safetensors
#
# silero_vad.onnx (snakers4/silero-vad, MIT) holds two networks behind an If
# on the sample rate; this takes the 16 kHz one's trained weights, as f32, by
# their PyTorch names. The STFT basis is left out: it is a periodic-Hann DFT
# (cos, -sin) to 7.7e-8, and src/silero.nu computes it.
# Needs: onnx, numpy.
import json, struct, sys
import numpy as np, onnx
from onnx import numpy_helper

NAMES = [
    "encoder.0.reparam_conv.weight", "encoder.0.reparam_conv.bias",
    "encoder.1.reparam_conv.weight", "encoder.1.reparam_conv.bias",
    "encoder.2.reparam_conv.weight", "encoder.2.reparam_conv.bias",
    "encoder.3.reparam_conv.weight", "encoder.3.reparam_conv.bias",
    "decoder.rnn.weight_ih", "decoder.rnn.weight_hh",
    "decoder.rnn.bias_ih", "decoder.rnn.bias_hh",
    "decoder.decoder.2.weight", "decoder.decoder.2.bias",
]

def weights(path):
    found = {}
    def walk(g):
        for n in g.node:
            out = n.output[0]
            if n.op_type == "Constant" and "If_0_then_branch__Inline_0__" in out:
                name = out.split("Inline_0__", 1)[1]
                if name in NAMES:
                    found[name] = numpy_helper.to_array(n.attribute[0].t).astype(np.float32)
            for a in n.attribute:
                if a.type == onnx.AttributeProto.GRAPH:
                    walk(a.g)
    walk(onnx.load(path).graph)
    missing = [n for n in NAMES if n not in found]
    if missing:
        sys.exit("not a Silero VAD v5 file — missing: " + ", ".join(missing))
    return found

def main():
    src, dst = sys.argv[1], sys.argv[2]
    w = weights(src)
    header, blobs, off = {"__metadata__": {"source": "snakers4/silero-vad v5 (MIT), 16 kHz branch"}}, [], 0
    for name in NAMES:
        a = np.ascontiguousarray(w[name])
        b = a.tobytes()
        header[name] = {"dtype": "F32", "shape": list(a.shape), "data_offsets": [off, off + len(b)]}
        blobs.append(b)
        off += len(b)
    h = json.dumps(header, separators=(",", ":")).encode()
    h += b" " * (-len(h) % 8)
    with open(dst, "wb") as f:
        f.write(struct.pack("<Q", len(h)))
        f.write(h)
        for b in blobs:
            f.write(b)
    print(f"{dst}: {len(NAMES)} tensors, {off} bytes of weights")

main()
