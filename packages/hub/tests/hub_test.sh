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
#       correct sha — a hub 0.2 partial file is taken over
#    7. PARALLEL: the repo again in 64 KiB ranges, 3 files × 4
#       connections at once — the oracle holds, nothing staged is left
#    8. RANGE RESUME: a staging file holding only the chunks its record
#       lists (the rest zeros) completes to the published sha
#    9. a corrupted range the record vouches for FAILS the sha256 check
#       (proof the recorded ranges are not fetched again) and the staging
#       state is discarded; the next fetch is clean
#   10. a hub 0.2 partial file feeds a ranged fetch its whole chunks
#   11. a real interruption: a second hub on the same file is refused
#       while the first runs; the first is killed (-9) mid-transfer, and
#       the rerun fetches only the chunks the record lacks
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

echo "[1/12] build hub"
$NURL src/main.nu "$HUB" >/dev/null 2>"$WORK/build.err" || { echo "build failed:"; tail -5 "$WORK/build.err"; exit 1; }

echo "[2/12] dir fetch → snapshot of symlinks"
DIR="$("$HUB" dir "$REPO" 2>"$WORK/e" | tail -1)" || { cat "$WORK/e"; fail "dir fetch"; }
[ -d "$DIR" ] || fail "snapshot dir missing"
[ -L "$DIR/model.safetensors" ] || fail "model.safetensors is not a symlink"
[ -f "$DIR/config.json" ] || fail "config.json not resolvable through the link"

echo "[3/12] ORACLE: LFS blob addresses == HF's published lfs.oid"
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

echo "[4/12] verify passes; corruption FAILS"
"$HUB" verify "$REPO" >/dev/null 2>&1 || fail "verify on a clean cache"
BLOB="$(ls "$NURL_MODELS"/blobs/sha256-* | head -1)"
printf 'Z' | dd of="$BLOB" bs=1 seek=0 count=1 conv=notrunc >/dev/null 2>&1
"$HUB" verify "$REPO" >/dev/null 2>&1 && fail "verify did NOT catch a flipped byte"
echo "   corruption detected"
# repair for the next steps
rm -rf "$NURL_MODELS"; "$HUB" dir "$REPO" >/dev/null 2>&1

echo "[5/12] single-file fetch dedups to the existing blob"
BEFORE="$(ls "$NURL_MODELS"/blobs | wc -l)"
"$HUB" file "$REPO/model.safetensors" >/dev/null 2>&1 || fail "single-file fetch"
AFTER="$(ls "$NURL_MODELS"/blobs | wc -l)"
[ "$BEFORE" = "$AFTER" ] || fail "single-file fetch added a blob instead of deduping ($BEFORE→$AFTER)"

echo "[6/12] rm GCs only unshared blobs"
"$HUB" rm "$REPO" >/dev/null 2>&1 || fail "rm repo"
REMAIN="$(ls "$NURL_MODELS"/blobs | wc -l)"
[ "$REMAIN" = "1" ] || fail "rm should leave the 1 blob shared with the file handle, left $REMAIN"
"$HUB" verify "$REPO/model.safetensors" >/dev/null 2>&1 || fail "shared file handle broke after repo rm"

echo "[7/12] resumed download completes to the correct sha"
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

oracle() {
python3 - "$API" "$1" <<'PY'
import json,sys,os,urllib.request
api,d=sys.argv[1],sys.argv[2]
tree=json.load(urllib.request.urlopen(api))
n=0
for e in tree:
    lfs=e.get("lfs")
    if not lfs: continue
    tgt=os.path.realpath(os.path.join(d,e["path"]))
    if os.path.basename(tgt)!="sha256-"+lfs["oid"]:
        print("  ",e["path"],"->",os.path.basename(tgt)); sys.exit(1)
    n+=1
print(f"   {n} LFS file(s) verified against the HF API")
PY
}
staged() { ls "$NURL_MODELS"/blobs | grep -E '\.part|\.ranges' ; }
CH=65536

echo "[8/12] PARALLEL: 64 KiB ranges, 3 files x 4 connections"
rm -rf "$NURL_MODELS"
DIR="$(HUB_CHUNK=$CH "$HUB" dir "$REPO" --jobs 3 --conns 4 2>"$WORK/e" | tail -1)" || { cat "$WORK/e"; fail "parallel dir fetch"; }
oracle "$DIR" || fail "parallel fetch: LFS provenance mismatch"
"$HUB" verify "$REPO" >/dev/null 2>&1 || fail "verify after the parallel fetch"
[ -z "$(staged)" ] || fail "staging files left after the parallel fetch: $(staged)"

# the 3.5 MB weight file: 55 chunks of 64 KiB
F="pytorch_model.bin"
cp "$NURL_MODELS/blobs/sha256-$TRUESHA" "$WORK/true.bin"
SZ=$(stat -c%s "$WORK/true.bin")
NC=$(( (SZ + CH - 1) / CH ))
PART="$NURL_MODELS/blobs/sha256-$TRUESHA.part"
MAP="$PART.ranges"
fresh() { rm -rf "$NURL_MODELS"; mkdir -p "$NURL_MODELS/blobs"; }

echo "[9/12] RANGE RESUME: only the recorded chunks on disk"
fresh
python3 - "$WORK/true.bin" "$PART" "$MAP" "$CH" <<'PY'
import sys
src,part,mp,ch=sys.argv[1],sys.argv[2],sys.argv[3],int(sys.argv[4])
data=open(src,'rb').read()
n=(len(data)+ch-1)//ch
out=bytearray(len(data))
rec=[k for k in range(n) if k%2==0]
for k in rec: out[k*ch:(k+1)*ch]=data[k*ch:(k+1)*ch]
open(part,'wb').write(out)
open(mp,'w').write("hub-ranges 1 %d %d\n"%(len(data),ch)+"".join("%d\n"%k for k in rec))
PY
HUB_CHUNK=$CH "$HUB" file "$REPO/$F" --conns 4 >/dev/null 2>"$WORK/e" || { cat "$WORK/e"; fail "range resume"; }
[ -f "$NURL_MODELS/blobs/sha256-$TRUESHA" ] || fail "range resume did not produce the published sha"
[ -z "$(staged)" ] || fail "staging files left after the range resume"

echo "[10/12] a corrupted recorded range FAILS the sha256 check"
fresh
python3 - "$WORK/true.bin" "$PART" "$MAP" "$CH" <<'PY'
import sys
src,part,mp,ch=sys.argv[1],sys.argv[2],sys.argv[3],int(sys.argv[4])
data=bytearray(open(src,'rb').read())
n=(len(data)+ch-1)//ch
data[ch+7]^=0xff                      # one flipped byte in chunk 1
data[5*ch:6*ch]=bytes(len(data[5*ch:6*ch]))   # chunk 5 missing: fetched
open(part,'wb').write(data)
open(mp,'w').write("hub-ranges 1 %d %d\n"%(len(data),ch)+"".join("%d\n"%k for k in range(n) if k!=5))
PY
HUB_CHUNK=$CH "$HUB" file "$REPO/$F" >/dev/null 2>"$WORK/e" && fail "a corrupted range was NOT caught"
grep -q "INTEGRITY FAILURE" "$WORK/e" || { cat "$WORK/e"; fail "the corrupted range failed for another reason"; }
[ -e "$NURL_MODELS/blobs/sha256-$TRUESHA" ] && fail "a corrupted file was stored as a blob"
[ -z "$(staged)" ] || fail "the corrupted staging state was kept"
HUB_CHUNK=$CH "$HUB" file "$REPO/$F" >/dev/null 2>&1 || fail "the fetch after a corrupted range"
[ -f "$NURL_MODELS/blobs/sha256-$TRUESHA" ] || fail "the fetch after a corrupted range: wrong sha"
echo "   corruption detected, discarded, refetched clean"

echo "[11/12] a hub 0.2 partial file feeds a ranged fetch"
fresh
head -c $(( SZ / 2 + 1000 )) "$WORK/true.bin" > "$NURL_MODELS/blobs/$F.part"
HUB_CHUNK=$CH "$HUB" file "$REPO/$F" >/dev/null 2>"$WORK/e" || { cat "$WORK/e"; fail "ranged fetch from a hub 0.2 partial"; }
[ -f "$NURL_MODELS/blobs/sha256-$TRUESHA" ] || fail "ranged fetch from a hub 0.2 partial: wrong sha"
[ -z "$(staged)" ] || fail "staging files left after the takeover"

echo "[12/12] a real interruption: lock, kill -9, resume"
fresh
HUB_CHUNK=$CH "$HUB" file "$REPO/$F" --conns 1 >/dev/null 2>&1 &
PID=$!
for _ in $(seq 1 300); do
    [ -f "$MAP" ] && [ "$(wc -l < "$MAP")" -ge 4 ] && break
    sleep 0.1
done
if [ -f "$MAP" ] && kill -0 $PID 2>/dev/null; then
    HUB_CHUNK=$CH "$HUB" file "$REPO/$F" >/dev/null 2>"$WORK/e2" && { kill -9 $PID; fail "a second hub fetched the file the first was fetching"; }
    grep -q "another hub" "$WORK/e2" || { kill -9 $PID; cat "$WORK/e2"; fail "the second hub failed for another reason"; }
    kill -9 $PID; wait $PID 2>/dev/null
    DONE1=$(( $(wc -l < "$MAP") - 1 ))
    [ "$DONE1" -ge 3 ] && [ "$DONE1" -lt "$NC" ] || fail "the record after the kill lists $DONE1 of $NC chunks"
    HUB_CHUNK=$CH "$HUB" file "$REPO/$F" >/dev/null 2>"$WORK/e" || { cat "$WORK/e"; fail "resume after kill -9"; }
    [ -f "$NURL_MODELS/blobs/sha256-$TRUESHA" ] || fail "resume after kill -9: wrong sha"
    [ -z "$(staged)" ] || fail "staging files left after the resume"
    echo "   killed with $DONE1/$NC chunks recorded; the rerun finished the rest"
else
    wait $PID 2>/dev/null
    echo "   (the transfer finished before it could be interrupted — interruption not exercised)"
fi

echo "PASS: all hub online gates"
