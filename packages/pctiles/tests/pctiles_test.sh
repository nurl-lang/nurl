#!/bin/sh
# packages/pctiles — tile a synthetic coloured terrain (120 000 points,
# written as an OpenCV-frame PLY: y down) and check the tileset against
# the cloud, independently of the code that made it:
#   - every input point is in exactly one tile, at its place turned to the
#     tileset's z-up frame (and through glTF's y-up in the content), with
#     its colour;
#   - every tile's points lie inside the tile's box;
#   - geometric errors fall downwards and are 0 at the leaves; the root
#     refines by ADD;
#   - the same seed gives the same tiles;
#   - --up +z leaves the points as they are.
# With VALIDATORS (node_modules/3d-tiles-validator and gltf-validator) the
# tileset and every tile also go through CesiumGS's and Khronos's
# validators: no errors, no warnings.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t pctiles-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
fails=0
[ -d deps/octree ] || nurlpkg install >/dev/null 2>&1
if ! $NURL src/main.nu "$WORK/pctiles" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
python3 - "$WORK/cloud.ply" <<'PY'
import math, random, struct, sys
random.seed(3)
pts = []
for i in range(120000):
    x, y = random.uniform(0, 40), random.uniform(0, 30)
    h = 2 * math.sin(x * 0.2) * math.cos(y * 0.15) + random.uniform(0, 0.05)
    # OpenCV: y down, so the height goes into -y; z is the second ground axis
    pts.append((x, -h, y, int(x * 6) % 256, int(y * 8) % 256, int((h + 2) * 60) % 256))
with open(sys.argv[1], "wb") as f:
    f.write(b"ply\nformat binary_little_endian 1.0\nelement vertex %d\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n" % len(pts))
    for p in pts: f.write(struct.pack("<fffBBB", *p))
PY
"$WORK/pctiles" build "$WORK/cloud.ply" -o "$WORK/a" --capacity 8000 --grid 32 -q || fails=$((fails + 1))
"$WORK/pctiles" build "$WORK/cloud.ply" -o "$WORK/b" --capacity 8000 --grid 32 -q > /dev/null || fails=$((fails + 1))
"$WORK/pctiles" build "$WORK/cloud.ply" -o "$WORK/z" --capacity 8000 --grid 32 --up +z -q > /dev/null || fails=$((fails + 1))
python3 - "$WORK" <<'PY' || fails=$((fails + 1))
import json, os, struct, sys
w = sys.argv[1]
bad = 0
def fail(m):
    global bad; bad += 1; print("FAIL", m)
def cloud():
    b = open(w + "/cloud.ply", "rb").read(); e = b.index(b"end_header\n") + 11
    n = (len(b) - e) // 15
    return [struct.unpack_from("<fffBBB", b, e + 15 * i) for i in range(n)]
def tiles(d):
    ts = json.load(open(d + "/tileset.json")); out = []
    if ts["root"].get("refine") != "ADD": fail("the root does not refine by ADD")
    def walk(t, perr, depth):
        if t["geometricError"] > perr: fail("an error rises downwards")
        if not t.get("children") and t["geometricError"] != 0: fail("a leaf with a non-zero error")
        bx = t["boundingVolume"]["box"]; c = bx[0:3]; h = (bx[3], bx[7], bx[11])
        b = open(os.path.join(d, t["content"]["uri"]), "rb").read()
        jl = struct.unpack_from("<I", b, 12)[0]; doc = json.loads(b[20:20 + jl]); binb = b[28 + jl:]
        prim = doc["meshes"][0]["primitives"][0]
        pa = doc["accessors"][prim["attributes"]["POSITION"]]; pv = doc["bufferViews"][pa["bufferView"]]
        ca = doc["accessors"][prim["attributes"]["COLOR_0"]]; cv = doc["bufferViews"][ca["bufferView"]]
        P = struct.unpack_from("<%df" % (3 * pa["count"]), binb, pv["byteOffset"])
        C = binb[cv["byteOffset"]:cv["byteOffset"] + 4 * ca["count"]]
        for k in range(pa["count"]):
            q = (P[3 * k], -P[3 * k + 2], P[3 * k + 1])  # glTF y-up → tileset z-up
            if any(abs(q[a] - c[a]) > h[a] + 1e-4 for a in range(3)): fail("a point outside its tile's box"); break
            out.append((round(q[0], 4), round(q[1], 4), round(q[2], 4), C[4 * k], C[4 * k + 1], C[4 * k + 2]))
        for ch in t.get("children", []): walk(ch, t["geometricError"], depth + 1)
    walk(ts["root"], ts["geometricError"], 0)
    return ts, out
src = cloud()
# OpenCV (x, y, z) → tileset z-up (x, z, -y)
want = sorted((round(x, 4), round(z, 4), round(-y, 4), r, g, b) for x, y, z, r, g, b in src)
ts, got = tiles(w + "/a")
if sorted(got) != want: fail("the tiles do not hold the cloud's points exactly once, in place, with their colours (%d vs %d)" % (len(got), len(want)))
else: print("PASS 120000 points, each in one tile, in place and coloured; boxes hold their points; errors fall to 0 at the leaves")
same = all(open(os.path.join(w, "a", f), "rb").read() == open(os.path.join(w, "b", f), "rb").read() for f in os.listdir(w + "/a"))
if not same or sorted(os.listdir(w + "/a")) != sorted(os.listdir(w + "/b")): fail("the same seed gave different tiles")
else: print("PASS the same seed gives byte-identical tiles")
_, gz = tiles(w + "/z")
wz = sorted((round(x, 4), round(y, 4), round(z, 4), r, g, b) for x, y, z, r, g, b in src)
if sorted(gz) != wz: fail("--up +z moved the points")
else: print("PASS --up +z keeps the points as they are")
sys.exit(1 if bad else 0)
PY
V="${VALIDATORS:-}"
if [ -n "$V" ] && [ -d "$V/node_modules/3d-tiles-validator" ] && [ -d "$V/node_modules/gltf-validator" ]; then
    out=$(cd "$V" && npx 3d-tiles-validator -t "$WORK/a/tileset.json" 2>&1)
    e=$(echo "$out" | sed -n 's/.*"numErrors": \([0-9]*\).*/\1/p' | head -1)
    wn=$(echo "$out" | sed -n 's/.*"numWarnings": \([0-9]*\).*/\1/p' | head -1)
    if [ "$e" = 0 ] && [ "$wn" = 0 ]; then echo "PASS CesiumGS 3d-tiles-validator: 0 errors, 0 warnings"
    else echo "FAIL CesiumGS 3d-tiles-validator: ${e:-?} errors, ${wn:-?} warnings"; fails=$((fails + 1)); fi
    cat > "$V/.pctiles-glb-check.mjs" <<'JS'
import { validateBytes } from "gltf-validator";
import { readFileSync, readdirSync } from "node:fs";
const d = process.argv[2]; let bad = 0, n = 0;
for (const f of readdirSync(d).filter((x) => x.endsWith(".glb"))) {
  const r = (await validateBytes(new Uint8Array(readFileSync(d + "/" + f)))).issues; n++;
  if (r.numErrors || r.numWarnings) bad++;
}
console.log((bad ? "FAIL" : "PASS") + " Khronos validator: " + n + " tiles, " + bad + " with errors or warnings");
process.exit(bad ? 1 : 0);
JS
    (cd "$V" && node .pctiles-glb-check.mjs "$WORK/a") || fails=$((fails + 1))
    rm -f "$V/.pctiles-glb-check.mjs"
else
    echo "SKIP the validators (set VALIDATORS to a dir with node_modules/3d-tiles-validator and gltf-validator)"
fi
[ "$fails" = 0 ] || exit 1
