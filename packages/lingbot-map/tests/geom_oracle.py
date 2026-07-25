#!/usr/bin/env python3
"""Reference output for tests/geomcheck.nu, straight from the upstream
lingbot_map torch code paths (quat_to_mat / mat_to_quat /
pose_encoding_to_extri_intri / closed_form_inverse_se3).

The pose encodings come from the same 64-bit LCG the NURL side runs, so
neither has to read a fixture: both generate identical inputs.
"""
import torch

H, W = 378, 518
MASK64 = (1 << 64) - 1


class Lcg:
    def __init__(self, seed):
        self.s = seed

    def __call__(self):
        self.s = (self.s * 6364136223846793005 + 1442695040888963407) & MASK64
        # NURL's `i` is signed: the multiply wraps into a two's-complement
        # 64-bit value, and `/ s 2048` is a SIGNED shift-like division.
        s = self.s - (1 << 64) if self.s >= (1 << 63) else self.s
        top = (s // 2048 if s >= 0 else -((-s) // 2048)) & 0xFFFFFFFF
        return top / 2147483648.0 - 1.0


def quat_to_mat(q):
    i, j, k, r = q.unbind(-1)
    two_s = 2.0 / (q * q).sum(-1)
    return torch.stack((
        1 - two_s * (j * j + k * k), two_s * (i * j - k * r), two_s * (i * k + j * r),
        two_s * (i * j + k * r), 1 - two_s * (i * i + k * k), two_s * (j * k - i * r),
        two_s * (i * k - j * r), two_s * (j * k + i * r), 1 - two_s * (i * i + j * j),
    ), -1).reshape(3, 3)


def _sqrt_positive_part(x):
    ret = torch.zeros_like(x)
    positive_mask = x > 0
    ret[positive_mask] = torch.sqrt(x[positive_mask])
    return ret


def mat_to_quat(matrix):
    m00, m01, m02, m10, m11, m12, m20, m21, m22 = matrix.reshape(9).unbind(-1)
    q_abs = _sqrt_positive_part(torch.stack([
        1.0 + m00 + m11 + m22, 1.0 + m00 - m11 - m22,
        1.0 - m00 + m11 - m22, 1.0 - m00 - m11 + m22], dim=-1))
    quat_by_rijk = torch.stack([
        torch.stack([q_abs[0] ** 2, m21 - m12, m02 - m20, m10 - m01], dim=-1),
        torch.stack([m21 - m12, q_abs[1] ** 2, m10 + m01, m02 + m20], dim=-1),
        torch.stack([m02 - m20, m10 + m01, q_abs[2] ** 2, m12 + m21], dim=-1),
        torch.stack([m10 - m01, m02 + m20, m12 + m21, q_abs[3] ** 2], dim=-1),
    ], dim=-2)
    flr = torch.tensor(0.1).to(dtype=q_abs.dtype)
    quat_candidates = quat_by_rijk / (2.0 * q_abs[..., None].max(flr))
    out = quat_candidates[q_abs.argmax(dim=-1), :]
    # scalar-last on the way out (upstream's standardize + [i,j,k,r] order)
    return torch.stack([out[1], out[2], out[3], out[0]])


def fmt(x):
    x = float(x)
    if x == int(x) and abs(x) < 1e15:
        return str(int(x))
    return repr(x)


def row(label, vals):
    print(label + "".join(" " + fmt(v) for v in vals))


def main():
    torch.set_default_dtype(torch.float64)
    lcg = Lcg(20260725)
    for case in range(6):
        print("case %d" % case)
        pe = [lcg() for _ in range(7)]
        pe.append(0.8 + 0.3 * lcg())
        pe.append(1.1 + 0.3 * lcg())
        pe_t = torch.tensor(pe, dtype=torch.float64)
        row("pe", pe)

        q = pe_t[3:7]
        R = quat_to_mat(q)
        row("R", R.reshape(9).tolist())
        row("q", mat_to_quat(R).tolist())

        extri = torch.cat([R, pe_t[:3, None]], dim=-1)
        row("extri", extri.reshape(12).tolist())

        fy = (H / 2.0) / torch.tan(pe_t[7] / 2.0)
        fx = (W / 2.0) / torch.tan(pe_t[8] / 2.0)
        K = torch.zeros(3, 3, dtype=torch.float64)
        K[0, 0], K[1, 1], K[0, 2], K[1, 2], K[2, 2] = fx, fy, W / 2, H / 2, 1.0
        row("intri", K.reshape(9).tolist())

        Ki = torch.zeros(3, 3, dtype=torch.float64)
        Ki[0, 0], Ki[1, 1] = 1.0 / fx, 1.0 / fy
        Ki[0, 2], Ki[1, 2] = -K[0, 2] / fx, -K[1, 2] / fy
        Ki[2, 2] = 1.0
        row("intri_inv", Ki.reshape(9).tolist())

        e4 = torch.eye(4, dtype=torch.float64)
        e4[:3, :] = extri
        c2w = torch.eye(4, dtype=torch.float64)
        c2w[:3, :3] = R.t()
        c2w[:3, 3] = -(R.t() @ pe_t[:3])
        row("c2w", c2w.reshape(16).tolist())

        for p in range(4):
            px, py, d = 137.0 * p, 91.0 * p, 0.5 + 2.0 * p
            ray = Ki @ torch.tensor([px, py, 1.0], dtype=torch.float64)
            cam = ray * d
            world = c2w[:3, :3] @ cam + c2w[:3, 3]
            row("xyz%d" % p, world.tolist())


if __name__ == "__main__":
    main()
