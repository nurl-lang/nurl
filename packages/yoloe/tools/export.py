import os, sys
os.chdir(sys.argv[1])
from ultralytics import YOLOE
model = YOLOE("yoloe-v8s-seg.pt")   # auto-downloads weights
model.eval()
# open-vocabulary prompt set (includes objects in the dog photo)
names = ["person","dog","cat","car","bicycle","truck","backpack","bottle","chair","bird"]
model.set_classes(names, model.get_text_pe(names))
path = model.export(format="onnx", opset=13, simplify=True, device="cpu")
print("EXPORTED", path)
print("NAMES", names)
