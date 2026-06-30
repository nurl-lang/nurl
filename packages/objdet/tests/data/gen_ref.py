import numpy as np, onnxruntime as ort, sys
from PIL import Image
d = sys.argv[1]
im = Image.open(d+'/dog.jpg').convert('RGB').resize((416,416), Image.BILINEAR)
# save PPM P6 (binary) for the NURL loader
with open(d+'/dog416.ppm','wb') as f:
    f.write(b'P6\n416 416\n255\n'); f.write(im.tobytes())
arr = np.asarray(im, dtype=np.float32)          # HWC [0,255]
chw = np.transpose(arr, (2,0,1))[None]          # 1,3,416,416
chw.astype(np.float32).tofile(d+'/input.f32')
sess = ort.InferenceSession(d+'/tinyyolov2-8.onnx', providers=['CPUExecutionProvider'])
inp = sess.get_inputs()[0].name
grid = sess.run(None, {inp: chw})[0].astype(np.float32)   # 1,125,13,13
grid.tofile(d+'/grid.f32')
print('input', chw.shape, 'grid', grid.shape, 'grid stats', grid.min(), grid.max(), grid.mean())

# reference decode (YOLOv2 VOC)
ANCHORS=[1.08,1.19,3.42,4.41,6.63,11.38,9.42,5.11,16.62,10.52]
VOC="aeroplane bicycle bird boat bottle bus car cat chair cow diningtable dog horse motorbike person pottedplant sheep sofa train tvmonitor".split()
def sig(x): return 1/(1+np.exp(-x))
g = grid[0]  # 125,13,13
dets=[]
for cy in range(13):
  for cx in range(13):
    for b in range(5):
      o=b*25
      tx,ty,tw,th,to = g[o:o+5, cy, cx]
      cls = g[o+5:o+25, cy, cx]
      x=(cx+sig(tx))/13; y=(cy+sig(ty))/13
      w=ANCHORS[2*b]*np.exp(tw)/13; h=ANCHORS[2*b+1]*np.exp(th)/13
      conf=sig(to); e=np.exp(cls-cls.max()); p=e/e.sum()
      ci=p.argmax(); score=conf*p[ci]
      if score>0.3: dets.append((score, VOC[ci], x,y,w,h))
dets.sort(reverse=True)
# simple NMS
def iou(a,b):
  ax,ay,aw,ah=a[2:]; bx,by,bw,bh=b[2:]
  a1x,a1y,a2x,a2y=ax-aw/2,ay-ah/2,ax+aw/2,ay+ah/2
  b1x,b1y,b2x,b2y=bx-bw/2,by-bh/2,bx+bw/2,by+bh/2
  ix=max(0,min(a2x,b2x)-max(a1x,b1x)); iy=max(0,min(a2y,b2y)-max(a1y,b1y))
  inter=ix*iy; un=aw*ah+bw*bh-inter
  return inter/un if un>0 else 0
keep=[]
for d_ in dets:
  if all(iou(d_,k)<0.45 or d_[1]!=k[1] for k in keep): keep.append(d_)
print("REFERENCE DETECTIONS:")
for s,c,x,y,w,h in keep:
    print(f"  {c:12s} {s:.3f}  box(cx={x:.3f} cy={y:.3f} w={w:.3f} h={h:.3f})")
