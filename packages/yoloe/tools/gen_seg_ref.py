"""Reference for the segmentation path: run the exported YOLOE-seg ONNX through
onnxruntime on a letterboxed image and dump output0, output1(proto), and the
decoded per-detection mask (process_mask) so the NURL implementation can be
verified numerically.

  python tools/gen_seg_ref.py <model.onnx> <image.jpg|ppm> <outdir>

Writes, into <outdir>:
  input.ppm        the 640x640 letterboxed input (what NURL must also build)
  proto.f32        output1 [1,32,160,160] raw little-endian float
  dets.txt         one line per detection: cls score x0 y0 w h (letterbox px)
  mask_NN.pgm      the upsampled+thresholded mask for detection NN (640x640)
"""
import sys, numpy as np, onnxruntime as ort
from PIL import Image

model, imgpath, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
S = 640

im = Image.open(imgpath).convert("RGB")
W, H = im.size
scale = min(S / W, S / H)
nw, nh = int(W * scale), int(H * scale)
padx, pady = (S - nw) // 2, (S - nh) // 2
resized = im.resize((nw, nh), Image.BILINEAR)
canvas = Image.new("RGB", (S, S), (114, 114, 114))
canvas.paste(resized, (padx, pady))
arr = np.asarray(canvas, dtype=np.float32) / 255.0  # HWC
x = arr.transpose(2, 0, 1)[None]  # 1,3,H,W

with open(f"{outdir}/input.ppm", "wb") as f:
    f.write(f"P6\n{S} {S}\n255\n".encode())
    f.write(np.asarray(canvas, dtype=np.uint8).tobytes())

sess = ort.InferenceSession(model, providers=["CPUExecutionProvider"])
outs = sess.run(None, {"images": x})
out0 = outs[0]                 # [1, 4+nc+32, 8400]
proto = outs[1]               # [1, 32, 160, 160]
print("out0", out0.shape, "proto", proto.shape)
proto.astype("<f4").tofile(f"{outdir}/proto.f32")

C = out0.shape[1]
nm = 32
nc = C - 4 - nm
na = out0.shape[2]
boxes = out0[0, :4, :]          # cx,cy,w,h (letterbox px)
cls = out0[0, 4:4 + nc, :]      # already sigmoid
coeffs = out0[0, 4 + nc:, :]    # 32 x na

conf = 0.25
iou = 0.5
best = cls.max(0)
bestc = cls.argmax(0)
keep = np.where(best > conf)[0]

def iou_xywh(a, b):
    ax1, ay1, ax2, ay2 = a[0]-a[2]/2, a[1]-a[3]/2, a[0]+a[2]/2, a[1]+a[3]/2
    bx1, by1, bx2, by2 = b[0]-b[2]/2, b[1]-b[3]/2, b[0]+b[2]/2, b[1]+b[3]/2
    ix = max(0, min(ax2, bx2) - max(ax1, bx1))
    iy = max(0, min(ay2, by2) - max(ay1, by1))
    inter = ix * iy
    un = a[2]*a[3] + b[2]*b[3] - inter
    return inter / un if un > 0 else 0

order = keep[np.argsort(-best[keep])]
picked = []
used = np.zeros(len(order), bool)
for i in range(len(order)):
    if used[i]:
        continue
    ai = order[i]
    picked.append(ai)
    for j in range(i+1, len(order)):
        if used[j]:
            continue
        aj = order[j]
        if bestc[ai] == bestc[aj] and iou_xywh(boxes[:, ai], boxes[:, aj]) > iou:
            used[j] = True

mh, mw = proto.shape[2:]
protoflat = proto[0].reshape(nm, -1)  # 32 x (mh*mw)
with open(f"{outdir}/dets.txt", "w") as f:
    for idx, ai in enumerate(picked):
        cx, cy, w, h = boxes[:, ai]
        x0, y0 = cx - w/2, cy - h/2
        c = int(bestc[ai])
        sc = float(best[ai])
        f.write(f"{c} {sc:.5f} {x0:.3f} {y0:.3f} {w:.3f} {h:.3f} {ai}\n")
        ml = (coeffs[:, ai] @ protoflat).reshape(mh, mw)  # logits 160x160
        # crop to downsampled box
        r = 0.25
        bx1, by1, bx2, by2 = x0*r, y0*r, (x0+w)*r, (y0+h)*r
        yy, xx = np.mgrid[0:mh, 0:mw]
        cropped = ml * ((xx >= bx1) & (xx < bx2) & (yy >= by1) & (yy < by2))
        # bilinear upsample to SxS
        up = np.asarray(Image.fromarray(cropped).resize((S, S), Image.BILINEAR))
        mask = (up > 0).astype(np.uint8) * 255
        with open(f"{outdir}/mask_{idx:02d}.pgm", "wb") as g:
            g.write(f"P5\n{S} {S}\n255\n".encode())
            g.write(mask.tobytes())
        print(f"det {idx}: cls={c} score={sc:.3f} box=({x0:.0f},{y0:.0f},{w:.0f},{h:.0f}) mask_px={int((mask>0).sum())}")
print("wrote refs to", outdir)
