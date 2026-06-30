import os, sys, torch, torch.nn as nn, collections
os.chdir(sys.argv[1])
from ultralytics import YOLOE
m = YOLOE("yoloe-v8s-seg.pt"); m.eval()
ym = m.model
names = ["person","dog","cat","car","bicycle","truck","backpack","bottle","chair","bird"]
tpe = m.get_text_pe(names)
ym.set_classes(names, tpe)          # sets nc=len(names); does NOT fuse
print("tpe shape", tuple(tpe.shape), "nc", ym.model[-1].nc)
class Promptable(nn.Module):
    def __init__(self, ym): super().__init__(); self.ym = ym
    def forward(self, image, tpe): return self.ym.predict(image, tpe=tpe)
wrap = Promptable(ym).eval()
img = torch.zeros(1,3,640,640)
with torch.no_grad(): out = wrap(img, tpe)
o = out[0] if isinstance(out,(list,tuple)) else out
print("forward OK, out shape", tuple(o.shape))
torch.onnx.export(wrap,(img,tpe),"yoloe-promptable.onnx",
    input_names=["images","tpe"],output_names=["output0"],
    opset_version=17, do_constant_folding=False)
import onnx
g=onnx.load("yoloe-promptable.onnx").graph
ops=collections.Counter(n.op_type for n in g.node)
print("PROMPTABLE ops:", dict(sorted(ops.items(),key=lambda x:-x[1])))
print("graph inputs:", [(i.name,[d.dim_value for d in i.type.tensor_type.shape.dim]) for i in g.input if i.name in {"images","tpe"}])
