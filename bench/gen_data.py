#!/usr/bin/env python3
# Generate a ~5 MB JSON file shared across the json_parse benchmarks.
# Stable shape so every language parses the same bytes.
import json, random, os
random.seed(42)
records = []
for i in range(500):
    records.append({
        "id": i,
        "name": f"record-{i:08d}",
        "score": round(random.random() * 1000, 4),
        "active": (i % 7) != 0,
        "tags": [f"tag{j}" for j in range(i % 5)],
        "meta": {"created": 1716000000 + i, "rev": i % 100},
    })
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.json")
with open(out, "w") as f:
    json.dump({"records": records}, f, separators=(",", ":"))
print(f"wrote {out} ({os.path.getsize(out)} bytes)")
