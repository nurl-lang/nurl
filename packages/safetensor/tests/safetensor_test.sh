#!/bin/sh
# ============================================================
#  packages/safetensor — test suite
#
#  1. selftest: crafted files that lie in every way a header can lie
#  2. a REAL model (whisper-tiny, 151 MB, 167 tensors): every tensor's
#     shape, dtype and byte extent must agree with an independent python
#     reader, and the f32 values of a sample of them must match to the bit
#  3. a truncated file must be a clean error, not a crash — the case that
#     actually happened while writing this package (a download cut short)
#
#  Run from the package dir:  ./tests/safetensor_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t safetensor.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] build"
if ! $NURL src/main.nu "$WORK/safetensor" >/dev/null 2>"$WORK/build.err"; then
    echo "  build FAILED"; cat "$WORK/build.err"; exit 1
fi
ST="$WORK/safetensor"

echo "[2/3] selftest — every lie a header can tell"
if "$ST" selftest | tail -1 | grep -q "0 failed"; then
    ok "$("$ST" selftest | tail -1)"
else
    bad "selftest"; "$ST" selftest | grep FAIL
fi

echo "[3/3] a real model, against an independent python reader"
M="$WORK/whisper-tiny.safetensors"
if curl -sL --max-time 900 -f -o "$M" \
    https://huggingface.co/openai/whisper-tiny/resolve/main/model.safetensors; then

    # every tensor: name, dtype, shape and extent must agree with python
    "$ST" tensors "$M" > "$WORK/ours.txt"
    python3 - "$M" "$WORK/ours.txt" <<'PYEOF' && ok "167 tensors: dtype, shape and byte extent == python" || bad "tensor table"
import sys, json, struct
raw = open(sys.argv[1], 'rb').read()
n = struct.unpack('<Q', raw[:8])[0]
hdr = json.loads(raw[8:8+n])
theirs = {}
for k, v in hdr.items():
    if k == '__metadata__': continue
    a, b = v['data_offsets']
    theirs[k] = (v['dtype'], list(v['shape']), b - a, 8 + n + a)
ours = {}
for line in open(sys.argv[2]):
    parts = line.split()
    name, dt = parts[0], parts[1]
    shape = [int(x.strip('[]')) for x in parts[2:-4]] if parts[2] != '[]' else []
    # "name DT [a b] NNN B @ OFF"
    lb = line.index('['); rb = line.index(']')
    shape = [int(x) for x in line[lb+1:rb].split()]
    tail = line[rb+1:].split()
    ours[name] = (dt, shape, int(tail[0]), int(tail[3]))
assert set(ours) == set(theirs), f"tensor set differs: {set(theirs) ^ set(ours)}"
for k in theirs:
    assert ours[k] == theirs[k], f"{k}: ours {ours[k]} != python {theirs[k]}"
print(f"    {len(theirs)} tensors agree")
PYEOF

    # the f32 values themselves — exported raw and compared BIT for bit, not
    # through printed decimals (which would only prove that the printer rounds)
    VALS_OK=1
    for T in model.encoder.conv1.weight model.encoder.layers.0.self_attn.q_proj.weight \
             model.decoder.embed_positions.weight model.decoder.layers.0.final_layer_norm.bias \
             model.decoder.embed_tokens.weight; do
        "$ST" export "$M" "$T" -o "$WORK/t.f32" >/dev/null 2>&1
        python3 - "$M" "$T" "$WORK/t.f32" <<'PYEOF' || VALS_OK=0
import sys, json, struct
raw = open(sys.argv[1], 'rb').read()
n = struct.unpack('<Q', raw[:8])[0]
hdr = json.loads(raw[8:8+n])
a, b = hdr[sys.argv[2]]['data_offsets']
want = raw[8+n+a:8+n+b]
got = open(sys.argv[3], 'rb').read()
assert got == want, f"{sys.argv[2]}: exported {len(got)} B, file has {len(want)} B, equal={got == want}"
PYEOF
    done
    [ "$VALS_OK" = "1" ] && ok "f32 values of 5 sampled tensors == the file, BIT for bit" \
                         || bad "exported values differ from the file"

    # a truncated file is a clean error — this really happened: the first
    # download was cut short, and the parser caught it before python did
    head -c 93346459 "$M" > "$WORK/truncated.safetensors"
    if "$ST" verify "$WORK/truncated.safetensors" >/dev/null 2>&1; then
        bad "truncated file accepted"
    else
        ok "truncated file (93 MB of 151 MB) is a clean error"
    fi

    # a file whose header is intact but whose data region is one byte short
    head -c $(($(stat -c%s "$M") - 1)) "$M" > "$WORK/short.safetensors"
    if "$ST" verify "$WORK/short.safetensors" >/dev/null 2>&1; then
        bad "file one byte short accepted"
    else
        ok "file one byte short is a clean error"
    fi
else
    echo "  SKIP real-model checks (download failed)"
fi

echo "== safetensor tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
