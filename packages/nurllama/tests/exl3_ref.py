# Fixtures for tests/exl3_test.nu: a random EXL3 linear and what exllamav3's
# own reference makes of it. The reference is exllamav3's tests/testlib/
# trellis.py — "independent NumPy / torch references for the EXL3 trellis
# format", which exllamav3 tests its kernels against — imported from an
# exllamav3 source tree, not copied: nurllama is checked against the same
# definition the format's authors check theirs.
#
# usage: exl3_ref.py <exllamav3-dir> <out.safetensors> <k> <n> <K> <codebook> <batch> <seed>
#   codebook: 3inst | mcg | mul1; K: 1..8, or 1.5 / 2.5 / 3.5 (mul1)
#   k, n: the linear's widths; it is STORED at kp, np — each rounded up to a
#   multiple of 128, as exllamav3 pads them (GLM's kv_a_proj: 576 → 640)
# writes  w.trellis (I16 [kp/16, np/16, 16K]), w.suh (F16 [kp]), w.svh (F16 [np]),
#         w.mcg / w.mul1 (the codebook marker, as exllamav3 stores it),
#         x  (F32 [batch, k])      a random input
#         wr (F32 [kp, np])        the reference's rotated-basis weight Ŵ
#         y  (F32 [batch, n])      the reference's x · W, in float64: x
#                                  zero-extended to kp, the first n outputs
import sys

import numpy as np
import torch
from safetensors.torch import save_file

sys.path.insert(0, sys.argv[1] + "/tests/testlib")
import trellis as ref  # noqa: E402

out, k, n, K, cb, batch, seed = sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), sys.argv[6], int(sys.argv[7]), int(sys.argv[8])
K = int(K) if K.is_integer() else K
gen = np.random.default_rng(seed)
kp, np_ = (k + 127) // 128 * 128, (n + 127) // 128 * 128
tk, tn = kp // 16, np_ // 16
trellis = ref.random_packed(tk * tn, K, gen).reshape(tk, tn, -1)
# signs with a scale, as a converter's suh / svh may carry
suh = (gen.choice([-1.0, 1.0], kp) * gen.uniform(0.5, 1.5, kp)).astype(np.float16)
svh = (gen.choice([-1.0, 1.0], np_) * gen.uniform(0.5, 1.5, np_)).astype(np.float16)
x = gen.standard_normal((batch, k)).astype(np.float32)

wr = ref.dequant_rotated(trellis, K, cb).astype(np.float32)
xp = np.zeros((batch, kp), dtype = np.float32)
xp[:, :k] = x
y = ref.linear(torch.from_numpy(xp), trellis, torch.from_numpy(suh), torch.from_numpy(svh), K, cb)[:, :n]

t = {
    "w.trellis": torch.from_numpy(np.ascontiguousarray(trellis)),
    "w.suh": torch.from_numpy(suh),
    "w.svh": torch.from_numpy(svh),
    "x": torch.from_numpy(x),
    "wr": torch.from_numpy(wr),
    "y": y.float().contiguous(),
}
if cb == "mcg":
    t["w.mcg"] = torch.from_numpy(np.array([0xCBAC1FED], dtype=np.uint32).view(np.int32))
elif cb == "mul1":
    t["w.mul1"] = torch.from_numpy(np.array([0x83DCD12D], dtype=np.uint32).view(np.int32))
save_file(t, out)
