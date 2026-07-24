#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/hub_test.sh — end-to-end test of the hub CLI against a real
#  (tiny) Hugging Face repository:
#    1. dir fetch materialises a snapshot dir of symlinks into blobs
#    2. THE ORACLE: every LFS blob's content address == the sha256 the
#       Hugging Face API publishes as lfs.oid (provenance, verified)
#    3. verify passes; a flipped byte makes verify FAIL (corruption is
#       an error, never bytes handed to a model)
#    4. a single-file fetch DEDUPS to the already-present blob
#    5. rm GCs only the blobs no other handle shares
#    6. a resumed download (seeded .part + Range) completes to the
#       correct sha
#
#  Run from the package dir:  ./tests/hub_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#  Network: needs huggingface.co; skips cleanly (exit 0) when offline.
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

REPO="hf-internal-testing/tiny-random-gpt2"
API="https://huggingface.co/api/models/$REPO/tree/main?recursive=1"

# network gate — skip gracefully if HF is unreachable
if ! curl -fsS --max-time 15 "$API" >/dev/null 2>&1; then
    echo "SKIP: huggingface.co unreachable — skipping online hub test"
    exit 0
fi

WORK="$(mktemp -d)"
export NURL_MODELS="$WORK/cache"
trap 'rm -rf "$WORK"' EXIT
HUB="$WORK/hub"
fail() { echo "FAIL: $1"; exit 1; }

echo "[1/7] build hub"
$NURL src/main.nu "$HUB" >/dev/null 2>"$WORK/build.err" || { echo "build failed:"; tail -5 "$WORK/build.err"; exit 1; }

echo "[2/7] dir fetch → snapshot of symlinks"
DIR="$("$HUB" dir "$REPO" 2>"$WORK/e" | tail -1)" || { cat "$WORK/e"; fail "dir fetch"; }
[ -d "$DIR" ] || fail "snapshot dir missing"
[ -L "$DIR/model.safetensors" ] || fail "model.safetensors is not a symlink"
[ -f "$DIR/config.json" ] || fail "config.json not resolvable through the link"

echo "[3/7] ORACLE: LFS blob addresses == HF's published lfs.oid"
# for each LFS file the API lists, the symlink must point at blobs/sha256-<lfs.oid>
python3 - "$API" "$DIR" <<'PY' || fail "LFS provenance mismatch"
import json,sys,os,urllib.request
api,d=sys.argv[1],sys.argv[2]
tree=json.load(urllib.request.urlopen(api))
n=0
for e in tree:
    lfs=e.get("lfs")
    if not lfs: continue
    link=os.path.join(d,e["path"])
    tgt=os.path.realpath(link)
    want="sha256-"+lfs["oid"]
    if os.path.basename(tgt)!=want:
        print("  ",e["path"],"->",os.path.basename(tgt),"expected",want); sys.exit(1)
    n+=1
print(f"   {n} LFS file(s) verified against the HF API")
PY

echo "[4/7] verify passes; corruption FAILS"
"$HUB" verify "$REPO" >/dev/null 2>&1 || fail "verify on a clean cache"
BLOB="$(ls "$NURL_MODELS"/blobs/sha256-* | head -1)"
printf 'Z' | dd of="$BLOB" bs=1 seek=0 count=1 conv=notrunc >/dev/null 2>&1
"$HUB" verify "$REPO" >/dev/null 2>&1 && fail "verify did NOT catch a flipped byte"
echo "   corruption detected"
# repair for the next steps
rm -rf "$NURL_MODELS"; "$HUB" dir "$REPO" >/dev/null 2>&1

echo "[5/7] single-file fetch dedups to the existing blob"
BEFORE="$(ls "$NURL_MODELS"/blobs | wc -l)"
"$HUB" file "$REPO/model.safetensors" >/dev/null 2>&1 || fail "single-file fetch"
AFTER="$(ls "$NURL_MODELS"/blobs | wc -l)"
[ "$BEFORE" = "$AFTER" ] || fail "single-file fetch added a blob instead of deduping ($BEFORE→$AFTER)"

echo "[6/7] rm GCs only unshared blobs"
"$HUB" rm "$REPO" >/dev/null 2>&1 || fail "rm repo"
REMAIN="$(ls "$NURL_MODELS"/blobs | wc -l)"
[ "$REMAIN" = "1" ] || fail "rm should leave the 1 blob shared with the file handle, left $REMAIN"
"$HUB" verify "$REPO/model.safetensors" >/dev/null 2>&1 || fail "shared file handle broke after repo rm"

echo "[7/7] resumed download completes to the correct sha"
rm -rf "$NURL_MODELS"; mkdir -p "$NURL_MODELS/blobs"
"$HUB" file "$REPO/pytorch_model.bin" >/dev/null 2>&1
TRUE="$(ls "$NURL_MODELS"/blobs/sha256-*)"; TRUESHA="$(basename "$TRUE" | sed 's/sha256-//')"
cp "$TRUE" "$WORK/true.bin"
rm -rf "$NURL_MODELS"; mkdir -p "$NURL_MODELS/blobs"
HALF=$(( $(stat -c%s "$WORK/true.bin") / 2 ))
head -c "$HALF" "$WORK/true.bin" > "$NURL_MODELS/blobs/pytorch_model.bin.part"
"$HUB" file "$REPO/pytorch_model.bin" >/dev/null 2>&1 || fail "resumed fetch"
GOTSHA="$(basename "$(ls "$NURL_MODELS"/blobs/sha256-*)" | sed 's/sha256-//')"
[ "$GOTSHA" = "$TRUESHA" ] || fail "resumed download produced the wrong sha ($GOTSHA vs $TRUESHA)"
[ -e "$NURL_MODELS"/blobs/*.part ] 2>/dev/null && fail ".part not cleaned up after resume"

echo "PASS: all hub online gates"
