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

echo "[1/5] the CLI builds"
if ! $NURL src/main.nu "$WORK/ply" >/dev/null 2>"$WORK/build.err"; then
    bad "build"; tail -6 "$WORK/build.err"
    echo; echo "$PASS passed, $FAIL failed, $SKIP skipped"; exit 1
else
    ok "built"
fi

echo "[2/5] --version agrees with nurl.toml"
manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
got=$("$WORK/ply" --version)
if [ "$got" = "ply $manifest" ]; then
    ok "version $manifest"
else
    bad "--version says '$got', manifest says '$manifest'"
fi

echo "[3/5] the writer, against an independent parser"
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

echo "[4/5] ply info"
vf=0
"$WORK/ply" info "$WORK/bin.ply" > "$WORK/info.txt" 2>&1 \
    || { bad "info failed"; cat "$WORK/info.txt"; vf=1; }
grep -q "^element vertex" "$WORK/info.txt" || { bad "info did not print the header"; vf=1; }
grep -q "^body " "$WORK/info.txt" || { bad "info did not print the body size"; vf=1; }
echo "not a ply" > "$WORK/nope.ply"
"$WORK/ply" info "$WORK/nope.ply" >/dev/null 2>&1
[ "$?" = "1" ] || { bad "info on a non-PLY should exit 1"; vf=1; }
[ "$vf" -eq 0 ] && ok "header printed, non-PLY refused"

echo "[5/5] the viewer serves, and renders in a real browser"
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
