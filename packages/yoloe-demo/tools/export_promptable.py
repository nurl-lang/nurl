# export_promptable.py — YOLOE-v8s-seg with a runtime text-prompt input,
# keeping BOTH outputs (detections + mask prototypes), folded to a fixed
# K=32 prompt-slot graph the NURL onnx runtime executes 1:1.
#
#   python export_promptable.py <workdir> [K]
#
# Needs: torch (cpu ok) + ultralytics + onnx + onnxsim. Downloads
# yoloe-v8s-seg.pt on first run. Writes yoloe-promptable-k<K>.onnx.
# The fixed K matters: onnxsim folds every Shape/Cast/dynamic-dim chain
# to constants, leaving only ops the NURL runtime supports; unused slots
# are fed zero embeddings at runtime (the graph's epsilon-clipped
# normalize keeps them inert, max score ~0.002).
import os, sys, collections
import torch, torch.nn as nn

workdir = sys.argv[1]
K = int(sys.argv[2]) if len(sys.argv) > 2 else 32
os.chdir(workdir)
from ultralytics import YOLOE

m = YOLOE("yoloe-v8s-seg.pt"); m.eval()
ym = m.model
names = ["person", "dog"]                    # seed only shapes the trace
tpe = m.get_text_pe(names).clone().detach()  # clone: escape inference mode
ym.set_classes(names, tpe)

class PromptableSeg(nn.Module):
    def __init__(self, ym): super().__init__(); self.ym = ym
    def forward(self, image, tpe):
        out = self.ym.predict(image, tpe=tpe)
        det, rest = out[0], out[1]
        proto = None
        if isinstance(rest, (list, tuple)):
            for t in rest:
                if torch.is_tensor(t) and t.dim() == 4 and t.shape[1] == 32:
                    proto = t
        elif torch.is_tensor(rest) and rest.dim() == 4:
            proto = rest
        return (det, proto) if proto is not None else det

wrap = PromptableSeg(ym).eval()
img = torch.zeros(1, 3, 640, 640)
with torch.no_grad(): out = wrap(img, tpe)
outnames = ["output0", "output1"] if isinstance(out, tuple) else ["output0"]
print("forward:", [tuple(t.shape) for t in out] if isinstance(out, tuple) else tuple(out.shape))

torch.onnx.export(wrap, (img, tpe), "yoloe-promptable-dyn.onnx",
    input_names=["images", "tpe"], output_names=outnames,
    opset_version=17, do_constant_folding=False, dynamo=False,
    dynamic_axes={"tpe": {1: "k"}, "output0": {1: "c"}})

import onnx
from onnxsim import simplify
mm = onnx.load("yoloe-promptable-dyn.onnx")
ms, ok = simplify(mm, overwrite_input_shapes={"images": [1,3,640,640], "tpe": [1,K,512]})
assert ok
onnx.save(ms, f"yoloe-promptable-k{K}.onnx")
ops = collections.Counter(n.op_type for n in ms.graph.node)
print("ops:", dict(sorted(ops.items(), key=lambda x: -x[1])))
print(f"wrote yoloe-promptable-k{K}.onnx")
