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

echo "[1/6] the CLI builds"
if ! $NURL src/main.nu "$WORK/ply" >/dev/null 2>"$WORK/build.err"; then
    bad "build"; tail -6 "$WORK/build.err"
    echo; echo "$PASS passed, $FAIL failed, $SKIP skipped"; exit 1
else
    ok "built"
fi

echo "[2/6] --version agrees with nurl.toml"
manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
got=$("$WORK/ply" --version)
if [ "$got" = "ply $manifest" ]; then
    ok "version $manifest"
else
    bad "--version says '$got', manifest says '$manifest'"
fi

echo "[3/6] the writer, against an independent parser"
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

echo "[4/6] ply info"
vf=0
"$WORK/ply" info "$WORK/bin.ply" > "$WORK/info.txt" 2>&1 \
    || { bad "info failed"; cat "$WORK/info.txt"; vf=1; }
grep -q "^element vertex" "$WORK/info.txt" || { bad "info did not print the header"; vf=1; }
grep -q "^body " "$WORK/info.txt" || { bad "info did not print the body size"; vf=1; }
echo "not a ply" > "$WORK/nope.ply"
"$WORK/ply" info "$WORK/nope.ply" >/dev/null 2>&1
[ "$?" = "1" ] || { bad "info on a non-PLY should exit 1"; vf=1; }
[ "$vf" -eq 0 ] && ok "header printed, non-PLY refused"

echo "[5/6] the reader: our own files back, others' layouts, refusals"
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
open(d + "/hand_plain.ply", "wb").write(head("binary_little_endian", [("float", "x"), ("float", "y"), ("float", "z")], 2) + b"end_header\n" + struct.pack("<ffffff", 1, 2, 3, 4, 5, 6))
# refusals
open(d + "/bad_be.ply", "wb").write(head("binary_big_endian", [("float", "x"), ("float", "y"), ("float", "z")], 1) + b"end_header\n" + struct.pack(">fff", 1, 2, 3))
open(d + "/bad_list.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y"), ("float", "z"), ("list uchar int", "idx")], 1) + b"end_header\n1 2 3 1 0\n")
open(d + "/bad_noz.ply", "wb").write(head("ascii", [("float", "x"), ("float", "y")], 1) + b"end_header\n1 2\n")
open(d + "/bad_order.ply", "wb").write(b"ply\nformat ascii 1.0\nelement face 0\nproperty list uchar int vertex_indices\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nend_header\n1 2 3\n")
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
for name, why in [("bad_be.ply", "binary_little_endian"), ("bad_list.ply", "list property"), ("bad_noz.ply", "no x, y and z"), ("bad_order.ply", "must come first"), ("bad_short.ply", "shorter than the header")]:
    if why not in got.get(name, ""): bad.append("%s should be refused for '%s': %s" % (name, why, got.get(name)))
if bad: print("\n".join(bad)); sys.exit(1)
print("our binary and ascii files read back (%d points); doubles, float colours, shorts, CRLF, extra properties and faces after the vertices read; 5 broken files refused with the reason" % n)
PYEOF
) && ok "$out" || bad "reader: $out"
fi

echo "[6/6] the viewer serves, and renders in a real browser"
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

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
