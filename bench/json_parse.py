#!/usr/bin/env python3
# json_parse — parse bench/data.json 20 times.
import json, os
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.json")
with open(path, "rb") as f:
    src = f.read()
ok = 0
for _ in range(20):
    obj = json.loads(src)
    if obj is not None:
        ok += 1
print(ok)
