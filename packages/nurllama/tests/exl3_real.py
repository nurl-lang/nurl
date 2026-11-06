# A tests/exl3_test.nu fixture from a REAL EXL3 linear: one tensor group of
# a published checkpoint, fetched with HTTP range requests (no multi-GB
# download), and exllamav3's own reference (tests/testlib/trellis.py) of it.
#
# usage: exl3_real.py <exllamav3-dir> <safetensors-url> <prefix> <n-real> <out.safetensors> <batch> <seed>
#   n-real: the linear's output width before exllamav3 padded it (the
#   stored svh is the padded one)
# writes the same tensors as exl3_ref.py: w.*, x, wr, y
import json
import struct
import sys
import urllib.request

import numpy as np
import torch
from safetensors.torch import save_file

sys.path.insert(0, sys.argv[1] + "/tests/testlib")
import trellis as ref  # noqa: E402

url, prefix, n_real, out, batch, seed = sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5], int(sys.argv[6]), int(sys.argv[7])


def fetch(a, b):
    req = urllib.request.Request(url, headers={"Range": "bytes=%d-%d" % (a, b - 1)})
    return urllib.request.urlopen(req, timeout=600).read()


hlen = struct.unpack("<Q", fetch(0, 8))[0]
header = json.loads(fetch(8, 8 + hlen))
DT = {"I16": np.int16, "F16": np.float16, "I32": np.int32}


def tensor(name):
    e = header[name]
    a, b = e["data_offsets"]
    return np.frombuffer(fetch(8 + hlen + a, 8 + hlen + b), dtype=DT[e["dtype"]]).reshape(e["shape"])


trellis = tensor(prefix + ".trellis")
suh = tensor(prefix + ".suh")
svh = tensor(prefix + ".svh")
cb = "mul1" if prefix + ".mul1" in header else "mcg" if prefix + ".mcg" in header else "3inst"
K = trellis.shape[2] / 16
K = int(K) if K.is_integer() else K
kp, np_ = trellis.shape[0] * 16, trellis.shape[1] * 16

gen = np.random.default_rng(seed)
x = gen.standard_normal((batch, kp)).astype(np.float32)
wr = ref.dequant_rotated(trellis, K, cb).astype(np.float32)
y = ref.linear(torch.from_numpy(x), trellis, torch.from_numpy(suh.copy()), torch.from_numpy(svh.copy()), K, cb)[:, :n_real]
t = {
    "w.trellis": torch.from_numpy(trellis.copy()),
    "w.suh": torch.from_numpy(suh.copy()),
    "w.svh": torch.from_numpy(svh.copy()),
    "x": torch.from_numpy(x),
    "wr": torch.from_numpy(wr),
    "y": y.float().contiguous(),
}
if cb != "3inst":
    t["w." + cb] = torch.from_numpy(tensor(prefix + "." + cb).copy().reshape(1))
save_file(t, out)
print("%s: %s K=%s, stored %dx%d" % (prefix, cb, K, kp, np_))
