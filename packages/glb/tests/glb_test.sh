#!/bin/sh
# packages/glb — write the test meshes and check every byte that matters
# without any dependency: the container, the chunks, each accessor inside
# its bufferView, indices in range, POSITION's min/max, unit normals, and
# triangles wound counter-clockwise around their normals. With
# GLTF_VALIDATOR pointing at a directory holding node_modules/gltf-validator
# (npm install gltf-validator), Khronos's own validator runs too and must
# report no error and no warning.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t glb-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
if ! $NURL tests/cube.nu "$WORK/cube" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the test program does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
if ! "$WORK/cube" "$WORK" > "$WORK/run.out"; then
    echo "FAIL the test program failed:"; cat "$WORK/run.out"; exit 1
fi
cat "$WORK/run.out"
fails=$(grep -c '^FAIL' "$WORK/run.out")

python3 - "$WORK/cube.glb" "$WORK/tri.glb" <<'PY' || fails=$((fails + 1))
import json, math, struct, sys
CT = {5121: ("B", 1), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}
bad = 0
def fail(f, m):
    global bad; bad += 1; print("FAIL", f, m)
for f in sys.argv[1:]:
    b = open(f, "rb").read()
    name = f.rsplit("/", 1)[-1]
    magic, ver, total = struct.unpack_from("<III", b, 0)
    if magic != 0x46546C67 or ver != 2 or total != len(b): fail(name, "bad header"); continue
    jl, jt = struct.unpack_from("<II", b, 12)
    if jt != 0x4E4F534A or jl % 4: fail(name, "bad JSON chunk"); continue
    doc = json.loads(b[20:20 + jl])
    bl, bt = struct.unpack_from("<II", b, 20 + jl)
    if bt != 0x004E4942 or bl % 4 or 28 + jl + bl != total: fail(name, "bad BIN chunk"); continue
    binb = b[28 + jl:28 + jl + bl]
    if doc["buffers"][0]["byteLength"] != bl: fail(name, "buffer length")
    def read(i):
        a = doc["accessors"][i]; v = doc["bufferViews"][a["bufferView"]]
        fmt, sz = CT[a["componentType"]]; n = NC[a["type"]]
        if v["byteOffset"] % 4: fail(name, "unaligned view")
        if a["count"] * n * sz > v["byteLength"] or v["byteOffset"] + v["byteLength"] > bl: fail(name, "accessor overruns its view")
        flat = struct.unpack_from("<%d%s" % (a["count"] * n, fmt), binb, v["byteOffset"])
        return a, [flat[k:k + n] for k in range(0, len(flat), n)]
    prim = doc["meshes"][0]["primitives"][0]
    pa, P = read(prim["attributes"]["POSITION"])
    for ax in range(3):
        if abs(min(p[ax] for p in P) - pa["min"][ax]) > 1e-6 or abs(max(p[ax] for p in P) - pa["max"][ax]) > 1e-6: fail(name, "min/max")
    _, I = read(prim["indices"])
    I = [i[0] for i in I]
    if len(I) % 3 or max(I) >= len(P): fail(name, "indices")
    if "NORMAL" in prim["attributes"]:
        _, N = read(prim["attributes"]["NORMAL"])
        if any(abs(math.sqrt(sum(c * c for c in n)) - 1) > 1e-5 for n in N): fail(name, "normals not unit")
        for t in range(0, len(I), 3):
            a, b2, c = (P[I[t]], P[I[t + 1]], P[I[t + 2]])
            u = [b2[k] - a[k] for k in range(3)]; v = [c[k] - a[k] for k in range(3)]
            cr = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
            if sum(cr[k] * N[I[t]][k] for k in range(3)) <= 0: fail(name, "triangle %d wound against its normal" % (t // 3)); break
    if "COLOR_0" in prim["attributes"]:
        ca, C = read(prim["attributes"]["COLOR_0"])
        if not ca.get("normalized") or len(C) != len(P): fail(name, "colours")
    print("PASS", name, "%d vertices, %d triangles" % (len(P), len(I) // 3))
sys.exit(1 if bad else 0)
PY

if [ -n "${GLTF_VALIDATOR:-}" ] && [ -d "$GLTF_VALIDATOR/node_modules/gltf-validator" ]; then
    cat > "$GLTF_VALIDATOR/.glb-check.mjs" <<'JS'
import { validateBytes } from "gltf-validator";
import { readFileSync } from "node:fs";
let bad = 0;
for (const f of process.argv.slice(2)) {
  const r = (await validateBytes(new Uint8Array(readFileSync(f)))).issues;
  const ok = r.numErrors === 0 && r.numWarnings === 0;
  if (!ok) bad++;
  console.log((ok ? "PASS" : "FAIL") + " Khronos validator " + f.split("/").pop() + ": " + r.numErrors + " errors, " + r.numWarnings + " warnings");
}
process.exit(bad ? 1 : 0);
JS
    (cd "$GLTF_VALIDATOR" && node .glb-check.mjs "$WORK/cube.glb" "$WORK/tri.glb") || fails=$((fails + 1))
    rm -f "$GLTF_VALIDATOR/.glb-check.mjs"
else
    echo "SKIP Khronos validator (set GLTF_VALIDATOR to a dir with node_modules/gltf-validator)"
fi
[ "$fails" = 0 ] || exit 1
