import os,sys,torch,torch.nn as nn,numpy as np,collections
os.chdir(sys.argv[1])
from ultralytics.nn.text_model import build_text_model
tm=build_text_model("mobileclip:blt",device="cpu")
tok=tm.tokenize(["dog"])           # single prompt -> [1,77]
class TE(nn.Module):
    def __init__(self,m): super().__init__(); self.m=m
    def forward(self,t): return self.m.encode_text(t)
wrap=TE(tm.model).eval()
with torch.no_grad(): out=wrap(tok)
out.numpy().astype(np.float32).tofile("text1_ref.f32")
tok.numpy().astype(np.int64).tofile("tokens1.i64")
# NO dynamic_axes -> static shapes (constant-folded)
torch.onnx.export(wrap,(tok,),"text1.onnx",input_names=["tokens"],output_names=["feats"],
    opset_version=17, do_constant_folding=True)
import onnx
onnx.save(onnx.load("text1.onnx"),"text1.onnx",save_as_external_data=False)
g=onnx.load("text1.onnx").graph
ops=collections.Counter(n.op_type for n in g.node)
print("STATIC text ops:", dict(sorted(ops.items(),key=lambda x:-x[1])))
print("out", tuple(out.shape), "ref[:4]", out.numpy().ravel()[:4])
