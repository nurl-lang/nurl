# export_text_encoder.py — MobileCLIP-blt text encoder as a single-prompt
# (n=1) ONNX graph the NURL runtime executes 1:1, output L2-normalized to
# match ultralytics get_text_pe.
#
#   python export_text_encoder.py <workdir>
#
# Needs: torch + ultralytics + onnx + onnxsim + onnxruntime + the
# traceable python mobileclip package
# (pip install git+https://github.com/ultralytics/mobileclip.git).
# Verifies parity against ultralytics' TS text model AND onnxruntime
# before writing. Fixing n=1 lets onnxsim fold the whole attention-mask
# construction (Trilu/Where/ConstantOfShape/Cast) to constants; the one
# remaining Flatten is rewritten as the equivalent Reshape.
import os, sys, collections
import torch, torch.nn as nn, numpy as np

os.chdir(sys.argv[1])
from ultralytics.nn.text_model import MobileCLIP, build_text_model

tm = MobileCLIP("blt", torch.device("cpu"))
ts = build_text_model("mobileclip:blt", device=torch.device("cpu"))
names = ["dog", "bicycle", "coffee mug"]
tok = tm.tokenizer(names).to(torch.int64)

class TextEnc(nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, tokens):
        f = self.m.encode_text(tokens)
        return f / f.norm(dim=-1, keepdim=True)

wrap = TextEnc(tm.model).eval()
with torch.no_grad():
    out = wrap(tok)
    ref_ts = ts.encode_text(ts.tokenize(names))
assert (out - ref_ts).abs().max().item() < 1e-3, "python MobileCLIP != ultralytics TS"

torch.onnx.export(wrap, (tok,), "text_encoder_dyn.onnx",
    input_names=["tokens"], output_names=["feats"],
    opset_version=17, do_constant_folding=True, dynamo=False,
    dynamic_axes={"tokens": {0: "n"}, "feats": {0: "n"}})

import onnx
from onnxsim import simplify
mm = onnx.load("text_encoder_dyn.onnx")
ms, ok = simplify(mm, overwrite_input_shapes={"tokens": [1, 77]})
assert ok
g = ms.graph
for i, n in enumerate(g.node):          # Flatten [1,77,512]→[77,512] ⇒ Reshape
    if n.op_type == "Flatten":
        shp = onnx.helper.make_tensor("flatten_shape_const", onnx.TensorProto.INT64,
                                      [2], np.array([77, 512], dtype=np.int64).tobytes(), raw=True)
        g.initializer.append(shp)
        rn = onnx.helper.make_node("Reshape", inputs=[n.input[0], "flatten_shape_const"],
                                   outputs=list(n.output), name="Flatten_as_Reshape")
        g.node.remove(n); g.node.insert(i, rn)
        break
onnx.save(ms, "text_encoder_n1.onnx")

import onnxruntime as ort
sess = ort.InferenceSession("text_encoder_n1.onnx")
for r in range(len(names)):
    o = sess.run(None, {"tokens": tok[r:r+1].numpy()})[0]
    d = float(np.abs(o - out[r].numpy()).max())
    assert d < 1e-4, f"row {r} diff {d}"
ops = collections.Counter(n.op_type for n in g.node)
print("ops:", dict(sorted(ops.items(), key=lambda x: -x[1])))
print("wrote text_encoder_n1.onnx (verified vs torch + onnxruntime)")
