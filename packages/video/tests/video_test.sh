#!/bin/sh
# ============================================================
#  packages/video — test suite
#
#  The fixture is an MJPEG AVI assembled by tests/make_avi.py (Pillow +
#  struct, no ffmpeg, no cv2), which doubles as documentation of the
#  container layout src/video.nu parses. What is asserted: the RIFF walk
#  finds the rate and the stream, the fps arithmetic keeps the right
#  frames, re-extraction REPLACES a previous run's frames rather than
#  mixing with them, and malformed input is an error, never a crash.
#
#  Run from the package dir:  ./tests/video_test.sh
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

WORK="$(mktemp -d -t video.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }

echo "[1/5] the CLI builds"
if ! $NURL src/main.nu "$WORK/video" >/dev/null 2>"$WORK/build.err"; then
    bad "build"; tail -6 "$WORK/build.err"
    echo; echo "$PASS passed, $FAIL failed, $SKIP skipped"; exit 1
else
    ok "built"
fi

echo "[2/5] --version agrees with nurl.toml"
manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
got=$("$WORK/video" --version)
if [ "$got" = "video $manifest" ]; then
    ok "version $manifest"
else
    bad "--version says '$got', manifest says '$manifest'"
fi

echo "[3/5] MJPEG AVI: probe, fps stride, re-extraction replaces"
if [ -z "$PY" ] || ! "$PY" -c "import PIL" 2>/dev/null; then
    skip "needs a python with Pillow"
else
    "$PY" tests/make_avi.py "$WORK/walk.avi" 12 synth:6 >/dev/null 2>&1
    vf=0
    "$WORK/video" probe "$WORK/walk.avi" > "$WORK/probe.txt" 2>&1 \
        || { bad "probe failed"; cat "$WORK/probe.txt"; vf=1; }
    grep -q "^fps        12" "$WORK/probe.txt" \
        || { bad "probe did not report 12 fps"; head -3 "$WORK/probe.txt"; vf=1; }
    # 12 fps at --fps 6 = every 2nd of 6 frames = 3
    "$WORK/video" frames "$WORK/walk.avi" --fps 6 > "$WORK/vid.txt" 2>&1 \
        || { bad "frames --fps 6 failed"; cat "$WORK/vid.txt"; vf=1; }
    n=$(ls "$WORK"/walk_frames/*.jpg 2>/dev/null | wc -l)
    [ "$n" = "3" ] || { bad "--fps 6 of a 12 fps video: expected 3 frames, found $n"; vf=1; }
    # full rate replaces, never mixes
    "$WORK/video" frames "$WORK/walk.avi" --fps 12 -q >/dev/null 2>&1
    n=$(ls "$WORK"/walk_frames/*.jpg 2>/dev/null | wc -l)
    [ "$n" = "6" ] || { bad "re-extraction left $n files, expected exactly 6"; vf=1; }
    # the frames must be JPEGs (magic FF D8)
    m=$(head -c 2 "$WORK/walk_frames/000000.jpg" | od -An -tu1 | tr -s " ")
    [ "$m" = " 255 216" ] || { bad "extracted frame is not a JPEG ($m)"; vf=1; }
    # --out lands them where told, and the bare-file shorthand works
    "$WORK/video" frames "$WORK/walk.avi" --fps 12 --out "$WORK/elsewhere" -q >/dev/null 2>&1
    n=$(ls "$WORK"/elsewhere/*.jpg 2>/dev/null | wc -l)
    [ "$n" = "6" ] || { bad "--out: expected 6 frames in elsewhere/, found $n"; vf=1; }
    [ "$vf" -eq 0 ] && ok "probe right, stride right, re-extraction replaces, --out lands"
fi

echo "[4/5] malformed input is an error, not a crash"
vf=0
printf 'RIFF\x04\x00\x00\x00AVI ' > "$WORK/trunc.avi"
"$WORK/video" frames "$WORK/trunc.avi" > "$WORK/trunc.txt" 2>&1
rc=$?
# no video stream: the parser must say so (or hand off to ffmpeg, which
# then fails cleanly) — anything but a crash
[ "$rc" = "1" ] || { bad "truncated AVI: expected exit 1, got $rc"; head -3 "$WORK/trunc.txt"; vf=1; }
head -c 65536 /dev/urandom > "$WORK/noise.avi" 2>/dev/null
"$WORK/video" frames "$WORK/noise.avi" >/dev/null 2>&1
rc=$?
[ "$rc" = "1" ] || { bad "random bytes: expected exit 1, got $rc"; vf=1; }
"$WORK/video" frames "$WORK/absent.avi" > "$WORK/absent.txt" 2>&1
rc=$?
grep -q "no such file" "$WORK/absent.txt" && [ "$rc" = "1" ] \
    || { bad "a missing file should say 'no such file' and exit 1"; vf=1; }
[ "$vf" -eq 0 ] && ok "truncated, random and missing inputs all fail cleanly"

echo "[5/5] non-AVI containers go to ffmpeg — or say what to do"
: > "$WORK/clip.mp4"
"$WORK/video" frames "$WORK/clip.mp4" > "$WORK/mp4.txt" 2>&1
rc=$?
if command -v ffmpeg >/dev/null 2>&1; then
    # an empty mp4 is not a video; ffmpeg must fail and be quoted
    if [ "$rc" = "1" ] && grep -q "ffmpeg" "$WORK/mp4.txt"; then
        ok "ffmpeg ran and its failure was reported"
    else
        bad "empty mp4 with ffmpeg on PATH: expected a quoted ffmpeg failure"
        head -3 "$WORK/mp4.txt"
    fi
else
    if [ "$rc" = "1" ] && grep -q "needs ffmpeg" "$WORK/mp4.txt"; then
        ok "without ffmpeg the error says what to install"
    else
        bad "expected the install-ffmpeg message"; head -3 "$WORK/mp4.txt"
    fi
fi

echo
echo "$PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
