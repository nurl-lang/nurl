import os,sys,torch,numpy as np
os.chdir(sys.argv[1])
from ultralytics.nn.text_model import build_text_model
names=[s.strip() for s in sys.argv[2].split(",")]
outbase=sys.argv[3]
tm=build_text_model("mobileclip:blt", device="cpu")
with torch.no_grad():
    raw=tm.encode_text(tm.tokenize(names)).reshape(1,len(names),-1).float()
raw.numpy().astype(np.float32).tofile(outbase+".f32")
open(outbase+".txt","w").write("\n".join(names)+"\n")
print(f"wrote {outbase}.f32 ({raw.shape}) + {outbase}.txt: {names}")
