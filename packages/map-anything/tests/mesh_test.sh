#!/bin/sh
# map-anything mesh without a GPU or the model: a synthetic scene file — a
# sphere seen by eight cameras around it, with exact depths — goes through
# the real TSDF fusion and marching tetrahedra, and the object must be the
# sphere: a valid .glb, its vertices on the sphere's surface, its normals
# and its triangles' winding pointing outward (in glTF's +Y-up frame,
# centred on the box). Also: a bad box and a truncated scene are refused.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t map-anything-mesh.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
if ! $NURL src/main.nu "$WORK/map-anything" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
fails=0

# the scene: sphere radius 0.4 at (0, 0, 2) in the camera-0 world frame
python3 - "$WORK/sphere.scene" <<'PY'
import math, struct, sys
W, H, F = 128, 96, 110.0
C, R = (0.0, 0.0, 2.0), 0.4
def norm(v):
    l = math.sqrt(sum(x * x for x in v)); return [x / l for x in v]
def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
out = bytearray(struct.pack("<III", 0x3153414D, H, W))
n = 0
for k in range(8):
    a = 2 * math.pi * k / 8
    el = 0.35 if k % 2 else -0.25
    eye = [C[0] + 1.6 * math.sin(a) * math.cos(el), C[1] + 1.6 * math.sin(el), C[2] - 1.6 * math.cos(a) * math.cos(el)]
    z = norm([C[i] - eye[i] for i in range(3)])            # camera forward
    x = norm(cross([0, 1, 0], z))                            # right (y down)
    y = cross(z, x)
    Rm = [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]   # columns: camera axes in world
    sim = [1.0] + [Rm[r][c] for r in range(3) for c in range(3)] + eye
    dz, mask, rgb = [], [], [[], [], []]
    for v in range(H):
        for u in range(W):
            dc = [(u - W / 2) / F, (v - H / 2) / F, 1.0]       # camera-frame ray with z = 1
            dw = [sum(Rm[r][c] * dc[c] for c in range(3)) for r in range(3)]
            oc = [eye[i] - C[i] for i in range(3)]
            A = sum(d * d for d in dw); B = 2 * sum(dw[i] * oc[i] for i in range(3)); Cc = sum(o * o for o in oc) - R * R
            disc = B * B - 4 * A * Cc
            if disc > 0:
                t = (-B - math.sqrt(disc)) / (2 * A)
                dz.append(t); mask.append(1)
            else:
                dz.append(0.0); mask.append(0)
            for ch, val in enumerate((200, 60, 40)): rgb[ch].append(val)
    out += struct.pack("<I", 0x57454956)
    out += struct.pack("<13d", *sim) + struct.pack("<4d", F, F, W / 2, H / 2)
    out += struct.pack("<%df" % (W * H), *dz) + bytes(mask) + bytes(rgb[0] + rgb[1] + rgb[2])
    n += 1
out += struct.pack("<II", 0x444E454D, n)
open(sys.argv[1], "wb").write(out)
PY

if "$WORK/map-anything" mesh "$WORK/sphere.scene" -o "$WORK/sphere.glb" --box -0.6 -0.6 1.4 0.6 0.6 2.6 --res 96 > "$WORK/mesh.out" 2>&1; then
    echo "PASS the mesh subcommand ran"
else
    echo "FAIL the mesh subcommand:"; tail -5 "$WORK/mesh.out"; fails=$((fails + 1))
fi

python3 - "$WORK/sphere.glb" <<'PY' || fails=$((fails + 1))
import json, math, struct, sys
b = open(sys.argv[1], "rb").read()
assert struct.unpack_from("<I", b, 0)[0] == 0x46546C67
jl = struct.unpack_from("<I", b, 12)[0]
doc = json.loads(b[20:20 + jl]); binb = b[28 + jl:]
prim = doc["meshes"][0]["primitives"][0]
def read(i):
    a = doc["accessors"][i]; v = doc["bufferViews"][a["bufferView"]]
    fmt = {5126: "f", 5125: "I", 5121: "B"}[a["componentType"]]; n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
    flat = struct.unpack_from("<%d%s" % (a["count"] * n, fmt), binb, v.get("byteOffset", 0))
    return [flat[k:k + n] for k in range(0, len(flat), n)]
P = read(prim["attributes"]["POSITION"]); N = read(prim["attributes"]["NORMAL"]); I = [i[0] for i in read(prim["indices"])]
bad = 0
# the box centre is (0, 0, 2), so the sphere's centre maps to the origin
r = [math.sqrt(sum(c * c for c in p)) for p in P]
cell = 1.2 / 96
off = max(abs(x - 0.4) for x in r)
if off > 2 * cell: print("FAIL vertices are off the sphere by up to %.4f m (cell %.4f)" % (off, cell)); bad += 1
else: print("PASS %d vertices on the sphere (worst %.4f m, cell %.4f)" % (len(P), off, cell))
outn = sum(1 for p, nn in zip(P, N) if sum(p[k] * nn[k] for k in range(3)) > 0) / len(P)
if outn < 0.99: print("FAIL only %.1f%% of the normals point outward" % (100 * outn)); bad += 1
else: print("PASS %.2f%% of the normals point outward" % (100 * outn))
ok = 0
for t in range(0, len(I), 3):
    a, b2, c = P[I[t]], P[I[t + 1]], P[I[t + 2]]
    u = [b2[k] - a[k] for k in range(3)]; v = [c[k] - a[k] for k in range(3)]
    cr = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    cen = [(a[k] + b2[k] + c[k]) / 3 for k in range(3)]
    if sum(cr[k] * cen[k] for k in range(3)) > 0: ok += 1
frac = ok / (len(I) // 3)
if frac < 0.99: print("FAIL only %.1f%% of the triangles wind outward" % (100 * frac)); bad += 1
else: print("PASS %d triangles, %.2f%% wound outward" % (len(I) // 3, 100 * frac))
C = read(prim["attributes"]["COLOR_0"])
red = sum(1 for c in C if c[0] > 150 and c[1] < 100) / len(C)
if red < 0.95: print("FAIL the sphere's colour did not come through (%.0f%% red)" % (100 * red)); bad += 1
else: print("PASS the colour came through")
sys.exit(1 if bad else 0)
PY

if "$WORK/map-anything" mesh "$WORK/sphere.scene" -o "$WORK/x.glb" --box 0 0 0 1 1 >/dev/null 2>&1; then
    echo "FAIL a five-number box was accepted"; fails=$((fails + 1))
else echo "PASS a five-number box is refused"; fi
head -c 1000 "$WORK/sphere.scene" > "$WORK/cut.scene"
if "$WORK/map-anything" mesh "$WORK/cut.scene" -o "$WORK/x.glb" > "$WORK/cut.out" 2>&1; then
    echo "FAIL a truncated scene was accepted"; fails=$((fails + 1))
else echo "PASS a truncated scene is refused: $(head -1 "$WORK/cut.out")"; fi
[ "$fails" = 0 ] || exit 1
