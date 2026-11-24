#!/bin/sh
# ============================================================
#  packages/ply — test suite
#
#  The writer is checked by an independent parser (python + struct):
#  the count `ply_finish` patched into the header must equal what the
#  parser finds in the body, and the binary and ascii spellings of the
#  same cloud must agree point for point. The viewer is checked by
#  serving a cloud and — when chrome/chromium is on PATH — rendering it
#  headlessly and counting lit pixels: a HUD that reports half a million
#  points over an empty canvas looks identical to a working viewer from
#  the DOM, so the DOM is not what gets asked.
#
#  Run from the package dir:  ./tests/ply_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

if [ -n "${PY:-}" ]; then :;
elif command -v python3 >/dev/null 2>&1; then PY="python3";
else PY=""; fi

WORK="$(mktemp -d -t ply.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

echo "[1/7] the CLI builds"
if ! $NURL src/main.nu "$WORK/ply" >/dev/null 2>"$WORK/build.err"; then
    bad "build"; tail -6 "$WORK/build.err"
    echo; echo "$PASS passed, $FAIL failed, $SKIP skipped"; exit 1
else
    ok "built"
fi

echo "[2/7] --version agrees with nurl.toml"
manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
got=$("$WORK/ply" --version)
if [ "$got" = "ply $manifest" ]; then
    ok "version $manifest"
else
    bad "--version says '$got', manifest says '$manifest'"
fi

echo "[3/7] the writer, against an independent parser"
if ! $NURL tests/writecheck.nu "$WORK/writecheck" >/dev/null 2>"$WORK/wc_build.err"; then
    bad "writecheck build"; tail -6 "$WORK/wc_build.err"
elif [ -z "$PY" ]; then
    skip "round-trip needs python3"
else
    vf=0
    nb=$("$WORK/writecheck" "$WORK/bin.ply" 0) || { bad "binary write failed"; vf=1; }
    na=$("$WORK/writecheck" "$WORK/asc.ply" 1) || { bad "ascii write failed"; vf=1; }
    [ "$nb" = "$na" ] || { bad "binary wrote $nb points, ascii $na"; vf=1; }
    out=$("$PY" - "$WORK/bin.ply" "$WORK/asc.ply" <<'PYEOF'
import struct, sys

def parse(path):
    data = open(path, "rb").read()
    end = data.index(b"end_header\n") + len(b"end_header\n")
    head = data[:end].decode()
    n = int([l for l in head.split("\n") if l.startswith("element vertex")][0].split()[-1])
    ascii_fmt = "format ascii" in head
    assert "comment writecheck" in head, "the comment line is missing"
    pts = []
    if ascii_fmt:
        lines = [l for l in data[end:].decode().split("\n") if l.strip()]
        assert len(lines) == n, "ascii body has %d lines, header says %d" % (len(lines), n)
        for l in lines:
            f = l.split()
            pts.append((float(f[0]), float(f[1]), float(f[2]),
                        int(f[3]), int(f[4]), int(f[5])))
    else:
        body = data[end:]
        assert len(body) == n * 15, "binary body is %d bytes, header says %d vertices" % (len(body), n)
        for i in range(n):
            x, y, z = struct.unpack_from("<fff", body, i * 15)
            r, g, b = body[i * 15 + 12], body[i * 15 + 13], body[i * 15 + 14]
            pts.append((x, y, z, r, g, b))
    return n, pts

nb, pb = parse(sys.argv[1])
na, pa = parse(sys.argv[2])
assert nb == na, "counts differ: %d vs %d" % (nb, na)
worst = 0.0
for (q, w) in zip(pb, pa):
    assert q[3:] == w[3:], "colours differ: %r vs %r" % (q, w)
    for a, b in zip(q[:3], w[:3]):
        worst = max(worst, abs(a - b))
# the ascii spelling goes through decimal text; float32 has ~7 digits
assert worst < 1e-6, "worst coordinate gap %g" % worst
print("%d points, binary and ascii agree (worst gap %g)" % (nb, worst))
PYEOF
) || { bad "round-trip: $out"; vf=1; }
    # the patched header must declare what the writer reported
    decl=$(head -c 512 "$WORK/bin.ply" | sed -n "s/^element vertex 0*\([0-9][0-9]*\).*/\1/p")
    [ "$decl" = "$nb" ] || { bad "header declares $decl, writer reported $nb"; vf=1; }
    [ "$vf" -eq 0 ] && ok "$out"
fi

echo "[4/7] ply info"
vf=0
"$WORK/ply" info "$WORK/bin.ply" > "$WORK/info.txt" 2>&1 \
    || { bad "info failed"; cat "$WORK/info.txt"; vf=1; }
grep -q "^element vertex" "$WORK/info.txt" || { bad "info did not print the header"; vf=1; }
grep -q "^body " "$WORK/info.txt" || { bad "info did not print the body size"; vf=1; }
echo "not a ply" > "$WORK/nope.ply"
"$WORK/ply" info "$WORK/nope.ply" >/dev/null 2>&1
[ "$?" = "1" ] || { bad "info on a non-PLY should exit 1"; vf=1; }
[ "$vf" -eq 0 ] && ok "header printed, non-PLY refused"

echo "[5/7] the reader: our own files back, others' layouts, refusals"
if ! $NURL tests/readcheck.nu "$WORK/readcheck" >/dev/null 2>"$WORK/rc_build.err"; then
    bad "readcheck build"; tail -6 "$WORK/rc_build.err"
elif [ -z "$PY" ]; then
    skip "the reader check needs python3"
else
    "$PY" - "$WORK" <<'PYEOF'
import struct, sys
d = sys.argv[1]
def head(fmt, props, n, extra=""):
    return ("ply\nformat %s 1.0\n%selement vertex %d\n%s" % (fmt, extra, n,
            "".join("property %s %s\n" % p for p in props))).encode()
# doubles, float colours 0..1, an extra property, faces after the vertices
props = [("double", "x"), ("double", "y"), ("double", "z"), ("float", "intensity"),
         ("float", "red"), ("float", "green"), ("float", "blue")]
pts = [(1.5, -2.25, 3.125, 9.0, 0.0, 0.5, 1.0), (-7.0, 0.0, 1e6, 1.0, 1.0, 0.25, 0.1)]
b = head("binary_little_endian", props, 2) + b"element face 1\nproperty list uchar int vertex_indices\nend_header\n"
for p in pts: b += struct.pack("<dddffff", *p)
b += struct.pack("<Biii", 3, 0, 1, 0)
open(d + "/hand_double.ply", "wb").write(b)
# ascii, short coordinates (negative too), uchar colours, CRLF lines
a = b"ply\r\nformat ascii 1.0\r\nelement vertex 3\r\nproperty short x\r\nproperty short y\r\nproperty short z\r\nproperty uchar red\r\nproperty uchar green\r\nproperty uchar blue\r\nend_header\r\n-3 4 5 10 20 30\r\n100 -200 300 1 2 3\r\n0 0 -32768 255 255 255\r\n"
open(d + "/hand_ascii.ply", "wb").write(a)
# positions only
# the last value ends the file, no newline after it
open(d + "/hand_eof.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y"), ("float", "z")], 1) + b"end_header\n0 0 0")
open(d + "/hand_plain.ply", "wb").write(head("binary_little_endian", [("float", "x"), ("float", "y"), ("float", "z")], 2) + b"end_header\n" + struct.pack("<ffffff", 1, 2, 3, 4, 5, 6))
# refusals
open(d + "/bad_be.ply", "wb").write(head("binary_big_endian", [("float", "x"), ("float", "y"), ("float", "z")], 1) + b"end_header\n" + struct.pack(">fff", 1, 2, 3))
open(d + "/bad_list.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y"), ("float", "z"), ("list uchar int", "idx")], 1) + b"end_header\n1 2 3 1 0\n")
open(d + "/bad_noz.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y")], 1) + b"end_header\n1 2\n")
open(d + "/bad_order.ply", "wb").write(b"ply\nformat ascii 1.0\nelement face 0\nproperty list uchar int vertex_indices\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1 2 3\n")
# a vertex line short of a value, with a face after it: CodeRabbit's case
open(d + "/bad_ascii_few.ply", "wb").write(b"ply\nformat ascii 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n1 2 3\n4 5\n3 0 1 0\n")
open(d + "/bad_ascii_many.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y"), ("float", "z")], 1) + b"end_header\n1 2 3 4\n")
# a header that claims a trillion vertices over 12 bytes: refused before any
# allocation (the test would run out of memory otherwise)
open(d + "/bad_huge.ply", "wb").write(head("binary_little_endian", [("float", "x"), ("float", "y"), ("float", "z")], 10**12) + b"end_header\n" + struct.pack("<fff", 1, 2, 3))
open(d + "/bad_short.ply", "wb").write(head("binary_little_endian", [("float", "x"), ("float", "y"), ("float", "z")], 5) + b"end_header\n" + struct.pack("<fff", 1, 2, 3))
PYEOF
    "$WORK/readcheck" "$WORK/bin.ply" "$WORK/asc.ply" "$WORK"/hand_*.ply "$WORK"/bad_*.ply > "$WORK/read.out" 2>&1
    out=$("$PY" - "$WORK" "$WORK/read.out" <<'PYEOF'
import struct, sys
d, outp = sys.argv[1], sys.argv[2]
got = {}
for l in open(outp):
    name, rest = l.split(" ", 1)
    got[name.rsplit("/", 1)[-1]] = rest.strip()
def fields(s): return dict(kv.split("=") for kv in s.split())
bad = []
def check(name, n, col, sxyz, srgb, first):
    g = got.get(name, "missing")
    if "refused" in g or g == "missing": bad.append("%s: %s" % (name, g)); return
    f = fields(g)
    fx = [float(v) for v in f.get("first", "nan,nan,nan").split(",")]
    if int(f["n"]) != n or int(f["col"]) != col or abs(float(f["sum"]) - sxyz) > 1e-3 * max(1, abs(sxyz)) or int(f["rgb"]) != srgb or any(abs(a - b) > 1e-6 * max(1, abs(b)) for a, b in zip(fx, first)):
        bad.append("%s: got %s, wanted n=%d col=%d sum=%g rgb=%d first=%r" % (name, g, n, col, sxyz, srgb, first))
# our writer's files, against an independent parse of the binary one
data = open(d + "/bin.ply", "rb").read()
end = data.index(b"end_header\n") + 11
n = int([l for l in data[:end].decode().split("\n") if l.startswith("element vertex")][0].split()[-1])
body = data[end:]
s = 0.0; r = 0
for i in range(n):
    x, y, z = struct.unpack_from("<fff", body, i * 15); s += x + y + z; r += sum(body[i * 15 + 12:i * 15 + 15])
first = struct.unpack_from("<fff", body, 0)
check("bin.ply", n, 1, s, r, first)
check("asc.ply", n, 1, s, r, first)
c255 = lambda v: max(0, min(255, int(v * 255 + 0.5)))
check("hand_double.ply", 2, 1, 1.5 - 2.25 + 3.125 - 7 + 0 + 1e6, c255(0) + c255(.5) + c255(1) + c255(1) + c255(.25) + c255(.1), (1.5, -2.25, 3.125))
check("hand_ascii.ply", 3, 1, -3 + 4 + 5 + 100 - 200 + 300 - 32768, 60 + 6 + 765, (-3, 4, 5))
check("hand_plain.ply", 2, 0, 21, 0, (1, 2, 3))
check("hand_eof.ply", 1, 0, 0, 0, (0, 0, 0))
for name, why in [("bad_be.ply", "binary_little_endian"), ("bad_list.ply", "list property"), ("bad_noz.ply", "no x, y and z"), ("bad_order.ply", "must come first"), ("bad_short.ply", "shorter than the header"), ("bad_ascii_few.ply", "fewer values"), ("bad_ascii_many.ply", "more values"), ("bad_huge.ply", "shorter than the header")]:
    if why not in got.get(name, ""): bad.append("%s should be refused for '%s': %s" % (name, why, got.get(name)))
if bad: print("\n".join(bad)); sys.exit(1)
print("our binary and ascii files read back (%d points); doubles, float colours, shorts, CRLF, extra properties and faces after the vertices read; 8 broken files refused with the reason (a short or long vertex line, a trillion-vertex header among them)" % n)
PYEOF
) && ok "$out" || bad "reader: $out"
fi

echo "[6/7] the viewer serves, and renders in a real browser"
VPORT="${PLY_VIEW_PORT:-8792}"
"$WORK/ply" view "$WORK/bin.ply" --port "$VPORT" > "$WORK/view.log" 2>&1 &
VPID=$!
up=0; i=0
while [ "$i" -lt 60 ]; do
    if curl -fsS -o /dev/null "http://127.0.0.1:$VPORT/" 2>/dev/null; then
        up=1; break
    fi
    i=$((i+1)); sleep 0.5
done
if [ "$up" != "1" ]; then
    bad "the viewer never came up on port $VPORT"; tail -3 "$WORK/view.log"
else
    vf=0
    curl -fsS "http://127.0.0.1:$VPORT/" > "$WORK/page.html" 2>/dev/null \
        || { bad "GET / failed"; vf=1; }
    grep -q "ply viewer" "$WORK/page.html" \
        || { bad "GET / did not return the viewer page"; vf=1; }
    curl -fsS "http://127.0.0.1:$VPORT/cloud" > "$WORK/got.ply" 2>/dev/null \
        || { bad "GET /cloud failed"; vf=1; }
    cmp -s "$WORK/bin.ply" "$WORK/got.ply" \
        || { bad "/cloud did not serve the file verbatim"; vf=1; }
    out="$(sh tests/viewer_shot.sh "http://127.0.0.1:$VPORT/?probe=6" \
            "$WORK/shot.png" 2>"$WORK/shot.err")"
    rc=$?
    if [ "$rc" = "77" ]; then
        skip "the render check needs chrome or chromium on PATH"
        [ "$vf" -eq 0 ] && ok "page and cloud served correctly"
    elif [ "$rc" != "0" ]; then
        bad "the viewer drew nothing"; echo "$out"; tail -2 "$WORK/shot.err"
    else
        lit=$(echo "$out" | sed -n 's/^lit \([0-9]*\)\/.*/\1/p')
        if [ "${lit:-0}" -lt 200 ]; then
            bad "only $lit pixels drawn — the cloud is not on screen"
        else
            [ "$vf" -eq 0 ] && ok "served and rendered — $out"
        fi
    fi
fi
kill "$VPID" 2>/dev/null
wait "$VPID" 2>/dev/null

echo "[7/7] the tileset client: a root with no content, a 503, a redirect, indexed points"
if [ -z "$PY" ]; then skip "the tileset client check needs python3"
elif ! command -v google-chrome >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1; then
    skip "the tileset client check needs chrome or chromium on PATH"
else
    SRV="$WORK/srv"; mkdir -p "$SRV"; cp views/viewer.html "$SRV/viewer.html"
    "$PY" - "$SRV" <<'PYEOF'
import json, os, struct, sys
d = sys.argv[1]
def glb(path, n, indexed=False, shift=0.0):
    pos = b"".join(struct.pack("<fff", (i % 20) * 0.05 + shift, (i // 20) * 0.05, 0.0) for i in range(n))
    col = b"".join(struct.pack("<BBBB", 200, 120 + i % 100, 60, 255) for i in range(n))
    idx = struct.pack("<%dI" % 4, 0, 1, 2, 3) if indexed else b""
    views = [{"buffer": 0, "byteOffset": 0, "byteLength": len(pos)}, {"buffer": 0, "byteOffset": len(pos), "byteLength": len(col)}]
    accs = [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3",
             "min": [shift, 0, 0], "max": [0.95 + shift, (n - 1) // 20 * 0.05, 0]},
            {"bufferView": 1, "componentType": 5121, "normalized": True, "count": n, "type": "VEC4"}]
    prim = {"attributes": {"POSITION": 0, "COLOR_0": 1}, "mode": 0}
    if indexed:
        views.append({"buffer": 0, "byteOffset": len(pos) + len(col), "byteLength": len(idx)})
        accs.append({"bufferView": 2, "componentType": 5125, "count": 4, "type": "SCALAR"}); prim["indices"] = 2
    binb = pos + col + idx
    doc = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
           "meshes": [{"primitives": [prim]}], "buffers": [{"byteLength": len(binb)}], "bufferViews": views, "accessors": accs}
    js = json.dumps(doc).encode(); js += b" " * (-len(js) % 4); binb += b"\0" * (-len(binb) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(binb)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binb), 0x004E4942) + binb
    os.makedirs(os.path.dirname(path), exist_ok=True); open(path, "wb").write(out)
def tile(uri=None, kids=(), cx=0.5, err=0.0):
    t = {"boundingVolume": {"box": [cx, 0, 0.5, 1, 0, 0, 0, 1, 0, 0, 0, 1]}, "geometricError": err}
    if uri: t["content"] = {"uri": uri}
    if kids: t["children"] = list(kids)
    return t
def tileset(path, root):
    root["refine"] = "ADD"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump({"asset": {"version": "1.1"}, "geometricError": 10, "root": root}, open(path, "w"))
# a root of no content over two point children
glb(d + "/structural/n1.glb", 400); glb(d + "/structural/n2.glb", 400, shift=1.0)
tileset(d + "/structural/tileset.json", tile(None, [tile("n1.glb"), tile("n2.glb", cx=1.5)], err=1.0))
# a root tile the server first answers 503 for
glb(d + "/flaky/n0.glb", 400); tileset(d + "/flaky/tileset.json", tile("n0.glb"))
# a manifest reached through a redirect: content resolves where it landed
glb(d + "/real/sub/n0.glb", 400); tileset(d + "/real/sub/tileset.json", tile("n0.glb"))
# point content with indices: refused, with the reason on screen
glb(d + "/indexed/n0.glb", 400, indexed=True); tileset(d + "/indexed/tileset.json", tile("n0.glb"))
# REPLACE: root content over a child of no content over a grandchild with content
glb(d + "/replace/r.glb", 400); glb(d + "/replace/g.glb", 400)
rt = tile("r.glb", [tile(None, [tile("g.glb")], err=0.5)], err=100.0)
os.makedirs(d + "/replace", exist_ok=True)
rt["refine"] = "REPLACE"
json.dump({"asset": {"version": "1.1"}, "geometricError": 200, "root": rt}, open(d + "/replace/tileset.json", "w"))
PYEOF
    cat > "$WORK/srv.py" <<'PYEOF'
import http.server, os, sys
root, port = sys.argv[1], int(sys.argv[2])
seen = set()
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=root, **k)
    def log_message(self, *a): pass
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/flaky/n0.glb" and p not in seen:
            seen.add(p); self.send_response(503); self.send_header("Content-Length", "0"); self.end_headers(); return
        if p == "/redir/tileset.json":
            self.send_response(302); self.send_header("Location", "/real/sub/tileset.json"); self.send_header("Content-Length", "0"); self.end_headers(); return
        return super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
    TPORT=$(( 23000 + $$ % 20000 ))
    "$PY" "$WORK/srv.py" "$SRV" "$TPORT" & TPID=$!
    for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$TPORT/viewer.html" && break; sleep 0.1; done
    tf=0
    for case in structural flaky redir; do
        out=$(sh tests/viewer_shot.sh "http://127.0.0.1:$TPORT/viewer.html?tiles=$case/tileset.json&probe=3" 2>&1 | tail -1)
        lit=$(echo "$out" | sed -n 's/^lit \([0-9]*\)\/.*/\1/p')
        [ "${lit:-0}" -ge 50 ] || { bad "tileset '$case' was not drawn: $out"; tf=1; }
    done
    out=$(sh tests/viewer_shot.sh "http://127.0.0.1:$TPORT/viewer.html?tiles=indexed/tileset.json&probe=3" 2>&1)
    echo "$out" | grep -q "indexed point content" || { bad "indexed point content was not refused with its reason: $(echo "$out" | tail -2)"; tf=1; }
    # REPLACE after a zoom in and out: in close, the grandchild loads; out
    # far, the walk stops at its content-less parent, so the root must be
    # drawn again — not left out because a grandchild nobody draws is loaded
    if command -v node >/dev/null 2>&1; then
        cat > "$WORK/replace.mjs" <<'JS'
import { spawn } from "node:child_process";
const [url, prof] = process.argv.slice(2);
const port = 9300 + Math.floor(Math.random() * 500);
const chrome = spawn("google-chrome", ["--headless=new", "--enable-unsafe-swiftshader", "--use-angle=swiftshader", "--no-sandbox",
  "--window-size=1000,800", `--remote-debugging-port=${port}`, `--user-data-dir=${prof}`, "about:blank"], { stdio: "ignore" });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let out = "no answer";
try {
  let t; for (let i = 0; i < 50; i++) { try { t = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); break; } catch { await sleep(200); } }
  const ws = new WebSocket(t.find((x) => x.type === "page").webSocketDebuggerUrl); await new Promise((r) => (ws.onopen = r));
  let n = 0; const w = new Map(); ws.onmessage = (m) => { const j = JSON.parse(m.data); if (j.id && w.has(j.id)) { w.get(j.id)(j); w.delete(j.id); } };
  const send = (method, params = {}) => new Promise((r) => { const k = ++n; w.set(k, r); ws.send(JSON.stringify({ id: k, method, params })); });
  const ev = async (e) => (await send("Runtime.evaluate", { expression: e, returnByValue: true })).result?.result?.value;
  await send("Page.navigate", { url });
  for (let i = 0; i < 100 && !(await ev("window.__ready === true")); i++) await sleep(100);
  await ev("cam.dist = 2; 0");
  for (let i = 0; i < 100 && (await ev("window.__tiles && window.__tiles.ready")) < 2; i++) await sleep(100);
  const near = JSON.parse(await ev("JSON.stringify(window.__tiles)"));
  await ev("cam.dist = 100; 0"); await sleep(1000);
  const far = JSON.parse(await ev("JSON.stringify(window.__tiles)"));
  out = `near ready=${near.ready} drawn=${near.drawnTiles}; far drawn=${far.drawnTiles}`;
  ws.close();
} finally { chrome.kill(); }
console.log(out);
JS
        r=$(timeout 90 node "$WORK/replace.mjs" "http://127.0.0.1:$TPORT/viewer.html?tiles=replace/tileset.json" "$WORK/chrome-replace" 2>&1)
        case "$r" in
            "near ready=2 drawn=1; far drawn=1") ;;
            *) bad "REPLACE after zooming in and out drew the wrong tiles: $r (want: near ready=2 drawn=1; far drawn=1)"; tf=1 ;;
        esac
    else skip "the REPLACE zoom check needs node"; fi
    kill "$TPID" 2>/dev/null; wait "$TPID" 2>/dev/null
    [ "$tf" -eq 0 ] && ok "a root with no content draws its first child; a 503 is retried; content resolves after a redirect; indexed points are refused, saying why; REPLACE draws its parent again when zoomed back out"
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
