import numpy as np, onnxruntime as ort, sys, os
from PIL import Image
wd=sys.argv[1]; os.chdir(wd)
names=["person","dog","cat","car","bicycle","truck","backpack","bottle","chair","bird"]
# letterbox dog.jpg to 640x640 (gray pad), like ultralytics
im=Image.open(sys.argv[2]).convert("RGB"); W,H=im.size
s=min(640/W,640/H); nw,nh=round(W*s),round(H*s)
r=im.resize((nw,nh),Image.BILINEAR)
canvas=Image.new("RGB",(640,640),(114,114,114))
ox,oy=(640-nw)//2,(640-nh)//2
canvas.paste(r,(ox,oy))
with open("dog640.ppm","wb") as f: f.write(b"P6\n640 640\n255\n"); f.write(canvas.tobytes())
arr=np.asarray(canvas,dtype=np.float32)/255.0
chw=np.transpose(arr,(2,0,1))[None]
chw.tofile("input.f32")
sess=ort.InferenceSession("yoloe-v8s-seg.onnx",providers=["CPUExecutionProvider"])
out=sess.run(None,{"images":chw})
o0=out[0].astype(np.float32)  # (1,46,8400)
o0.tofile("output0.f32")
print("input",chw.shape,"output0",o0.shape,"letterbox ox,oy,s",ox,oy,round(s,4))
# decode: rows = [cx,cy,w,h, cls0..cls9, mask0..31] in channel dim (46)
o=o0[0]  # 46,8400
box=o[:4]; cls=o[4:4+10]
dets=[]
for i in range(8400):
    c=cls[:,i]; ci=c.argmax(); sc=c[ci]
    if sc>0.25:
        cx,cy,w,h=box[:,i]
        dets.append((sc,names[ci],cx,cy,w,h))
dets.sort(reverse=True)
def iou(a,b):
    ax,ay,aw,ah=a[2:6]; bx,by,bw,bh=b[2:6]
    ax1,ay1,ax2,ay2=ax-aw/2,ay-ah/2,ax+aw/2,ay+ah/2
    bx1,by1,bx2,by2=bx-bw/2,by-bh/2,bx+bw/2,by+bh/2
    ix=max(0,min(ax2,bx2)-max(ax1,bx1)); iy=max(0,min(ay2,by2)-max(ay1,by1))
    inter=ix*iy; un=aw*ah+bw*bh-inter; return inter/un if un>0 else 0
keep=[]
for d in dets:
    if all(iou(d,k)<0.5 or d[1]!=k[1] for k in keep): keep.append(d)
print("REFERENCE DETECTIONS (letterboxed 640 coords):")
for sc,nm,cx,cy,w,h in keep[:15]:
    print(f"  {nm:10s} {sc:.3f}  cx={cx:.1f} cy={cy:.1f} w={w:.1f} h={h:.1f}")
