#!/bin/sh
# packages/tiles3d — write a small terrain tileset (21 point tiles, two
# levels below the root, ADD refinement) and the tilesets ts_json must
# refuse, then check what a client relies on, without any dependency:
#   - the tree: one root with refine, geometric errors never rising
#     downwards, the tileset's error at least the root's;
#   - every tile's content exists, is a POINTS glb, and each of its points
#     lies inside the tile's box once turned from glTF's y-up to the
#     tileset's z-up (x, -z, y);
#   - every terrain point is in exactly one tile (ADD: nothing twice).
# With VALIDATORS pointing at a directory holding node_modules/
# 3d-tiles-validator and node_modules/gltf-validator, CesiumGS's tileset
# validator and Khronos's glTF validator run too and must report no error
# and no warning. (The tileset validator alone passes a tile whose content
# it cannot recognise, so every glb also goes through Khronos's.)
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t tiles3d-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
if ! $NURL tests/terrain.nu "$WORK/terrain" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the test program does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
mkdir -p "$WORK/ts"
if ! "$WORK/terrain" "$WORK/ts" > "$WORK/run.out"; then
    echo "FAIL the test program failed:"; cat "$WORK/run.out"; exit 1
fi
cat "$WORK/run.out"
fails=$(grep -c '^FAIL' "$WORK/run.out")
refused=$(grep -c '^refused: ' "$WORK/run.out")
if [ "$refused" = 7 ]; then echo "PASS 7 broken tilesets refused, each with its reason"
else echo "FAIL $refused of 7 broken tilesets refused"; fails=$((fails + 1)); fi

python3 - "$WORK/ts" <<'PY' || fails=$((fails + 1))
import json, os, struct, sys
d = sys.argv[1]
ts = json.load(open(os.path.join(d, "tileset.json")))
bad = 0
def fail(m):
    global bad; bad += 1; print("FAIL", m)
if ts.get("asset", {}).get("version") != "1.1": fail("asset.version is not 1.1")
root = ts["root"]
if root.get("refine") not in ("ADD", "REPLACE"): fail("the root has no refine")
if ts["geometricError"] < root["geometricError"]: fail("tileset error below the root's")
seen = {}
tiles = 0
def points(path):
    b = open(path, "rb").read()
    magic, ver, total = struct.unpack_from("<III", b, 0)
    if magic != 0x46546C67 or total != len(b): fail(path + ": not a glb"); return []
    jl = struct.unpack_from("<I", b, 12)[0]
    doc = json.loads(b[20:20 + jl]); binb = b[28 + jl:]
    prim = doc["meshes"][0]["primitives"][0]
    if prim.get("mode") != 0: fail(path + ": not POINTS")
    a = doc["accessors"][prim["attributes"]["POSITION"]]
    v = doc["bufferViews"][a["bufferView"]]
    f = struct.unpack_from("<%df" % (3 * a["count"]), binb, v["byteOffset"])
    return [(f[k], -f[k + 2], f[k + 1]) for k in range(0, len(f), 3)]  # glTF y-up → z-up
def walk(t, perr, depth):
    global tiles
    tiles += 1
    if t["geometricError"] > perr: fail("a tile's error is above its parent's")
    bx = t["boundingVolume"]["box"]
    c, h = bx[0:3], (bx[3], bx[7], bx[11])
    if "content" in t:
        p = os.path.join(d, t["content"]["uri"])
        if not os.path.exists(p): fail("missing content " + p)
        else:
            out = 0
            for q in points(p):
                if any(abs(q[k] - c[k]) > h[k] + 1e-5 for k in range(3)): out += 1
                key = (round(q[0], 4), round(q[1], 4))
                seen[key] = seen.get(key, 0) + 1
            if out: fail("%s: %d points outside the tile's box" % (t["content"]["uri"], out))
    for ch in t.get("children", []): walk(ch, t["geometricError"], depth + 1)
walk(root, ts["geometricError"], 0)
if tiles != 21: fail("%d tiles, not 21" % tiles)
if len(seen) != 64 * 64 or any(n != 1 for n in seen.values()): fail("terrain points: %d distinct, some twice" % len(seen))
if not bad: print("PASS 21 tiles: one tree, errors fall downwards, every point inside its tile, each of 4096 once")
sys.exit(1 if bad else 0)
PY

V="${VALIDATORS:-}"
if [ -n "$V" ] && [ -d "$V/node_modules/3d-tiles-validator" ] && [ -d "$V/node_modules/gltf-validator" ]; then
    out=$(cd "$V" && npx 3d-tiles-validator -t "$WORK/ts/tileset.json" 2>&1)
    e=$(echo "$out" | sed -n 's/.*"numErrors": \([0-9]*\).*/\1/p' | head -1)
    w=$(echo "$out" | sed -n 's/.*"numWarnings": \([0-9]*\).*/\1/p' | head -1)
    if [ "$e" = 0 ] && [ "$w" = 0 ]; then echo "PASS CesiumGS 3d-tiles-validator: 0 errors, 0 warnings"
    else echo "FAIL CesiumGS 3d-tiles-validator: ${e:-?} errors, ${w:-?} warnings"; echo "$out" | tail -20; fails=$((fails + 1)); fi
    cat > "$V/.tiles3d-glb-check.mjs" <<'JS'
import { validateBytes } from "gltf-validator";
import { readFileSync } from "node:fs";
let bad = 0, n = 0;
for (const f of process.argv.slice(2)) {
  const r = (await validateBytes(new Uint8Array(readFileSync(f)))).issues;
  n++;
  if (r.numErrors || r.numWarnings) { bad++; console.log("FAIL Khronos validator " + f.split("/").pop() + ": " + r.numErrors + " errors, " + r.numWarnings + " warnings"); }
}
if (!bad) console.log("PASS Khronos validator: " + n + " tile contents, 0 errors, 0 warnings");
process.exit(bad ? 1 : 0);
JS
    (cd "$V" && node .tiles3d-glb-check.mjs "$WORK"/ts/*.glb) || fails=$((fails + 1))
    rm -f "$V/.tiles3d-glb-check.mjs"
else
    echo "SKIP the validators (set VALIDATORS to a dir with node_modules/3d-tiles-validator and gltf-validator)"
fi
[ "$fails" = 0 ] || exit 1
