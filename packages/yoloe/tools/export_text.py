import os,sys,torch,torch.nn as nn,numpy as np,collections
os.chdir(sys.argv[1])
from ultralytics.nn.text_model import build_text_model
tm=build_text_model("mobileclip:blt",device="cpu")
names=["dog","bicycle"]
tok=tm.tokenize(names)            # [N, ctxlen] int
print("tokens shape", tuple(tok.shape), "dtype", tok.dtype)
class TextEnc(nn.Module):
    def __init__(self,m): super().__init__(); self.m=m
    def forward(self,tokens): return self.m.encode_text(tokens)
wrap=TextEnc(tm.model).eval()
with torch.no_grad(): out=wrap(tok)
print("out shape", tuple(out.shape))
out.numpy().astype(np.float32).tofile("text_ref.f32")
tok.numpy().astype(np.int64).tofile("tokens.i64")
torch.onnx.export(wrap,(tok,),"text_encoder.onnx",input_names=["tokens"],output_names=["feats"],
    opset_version=17, do_constant_folding=True, dynamic_axes={"tokens":{0:"n"},"feats":{0:"n"}})
import onnx
m=onnx.load("text_encoder.onnx")
onnx.save(m,"text_encoder.onnx",save_as_external_data=False)  # force inline
g=onnx.load("text_encoder.onnx").graph
ops=collections.Counter(n.op_type for n in g.node)
print("TEXT ENCODER ops:", dict(sorted(ops.items(),key=lambda x:-x[1])))
print("inputs", [(i.name,[d.dim_value or d.dim_param for d in i.type.tensor_type.shape.dim]) for i in g.input])
print("outputs", [(o.name,[d.dim_value or d.dim_param for d in o.type.tensor_type.shape.dim]) for o in g.output])
