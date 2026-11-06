#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/exl3_test.sh — EXL3 weights (exllamav3's trellis quantisation)
#  against exllamav3's own reference, tests/testlib/trellis.py.
#
#  For every codebook (3INST, MCG, MUL1) at several bitrates — including a
#  half-integer one and the ones fiore-lab's GLM-5.3 uses (MCG 3 and 4 bits
#  for the experts, MUL1 5 bits for the other linears) — and at GLM-5.3's
#  shapes — padded ones too (GLM's kv_a_proj: 576 outputs stored as 640) —
#  a random EXL3 linear (tests/exl3_ref.py) must
#    1. decode to the reference's Ŵ bit for bit (lk_exl3_dequant)
#    2. give the reference's x · W through lk_matvec (both Hadamard
#       rotations and the trellis matvec)
#  on the CPU backend and, when there is one, the GPU.
#
#  Needs python3 with numpy, torch and safetensors, and an exllamav3 source
#  tree (EXLLAMAV3=/path/to/exllamav3, or NURL_NET_TESTS=1 to clone it).
#
#  Run from the package dir:  ./tests/exl3_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
PY="${PYTHON:-python3}"

WORK="$(mktemp -d -t nurllama-exl3.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

for d in gguf safetensor tokenizer gpu http grad nn gpukit tensor hub nurldb; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

if ! "$PY" -c 'import numpy, torch, safetensors' >/dev/null 2>&1; then
    echo "  SKIP (python3 with numpy, torch and safetensors required)"; exit 0
fi
EX="${EXLLAMAV3:-}"
if [ -z "$EX" ]; then
    if [ "${NURL_NET_TESTS:-0}" != 1 ] || ! command -v git >/dev/null 2>&1; then
        echo "  SKIP (set EXLLAMAV3 to an exllamav3 source tree, or NURL_NET_TESTS=1 with git)"; exit 0
    fi
    EX="$WORK/exllamav3"
    git clone -q --depth 1 https://github.com/turboderp-org/exllamav3 "$EX" || { echo "  SKIP clone failed"; exit 0; }
fi
[ -f "$EX/tests/testlib/trellis.py" ] || { echo "  SKIP ($EX has no tests/testlib/trellis.py)"; exit 0; }

echo "[1/3] build the EXL3 test"
if ! $NURL tests/exl3_test.nu "$WORK/exl3_test" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tests/exl3_test.nu:"; tail -5 "$WORK/build.err"; exit 1
fi

echo "[2/3] every codebook and bitrate, against exllamav3's reference"
backends="cpu"
[ "${NURL_GPU:-}" != cpu ] && backends="cpu default"
# k n K codebook batch
while read -r k n K cb batch; do
    f="$WORK/f.safetensors"
    if ! "$PY" tests/exl3_ref.py "$EX" "$f" "$k" "$n" "$K" "$cb" "$batch" 7 2>"$WORK/ref.err"; then
        echo "  FAIL fixture $cb K=$K ${k}x$n:"; tail -3 "$WORK/ref.err"; FAIL=$((FAIL+1)); continue
    fi
    for be in $backends; do
        if [ "$be" = cpu ]; then out=$(NURL_GPU=cpu EXL3_FIXTURE="$f" "$WORK/exl3_test" 2>&1); rc=$?
        else out=$(EXL3_FIXTURE="$f" "$WORK/exl3_test" 2>&1); rc=$?; fi
        np=$(grep -c "^  PASS" <<<"$out"); nf=$(grep -c "^  FAIL" <<<"$out")
        if [ "$rc" = 0 ] && [ "$np" = 2 ]; then
            echo "  PASS $cb K=$K ${k}x$n batch $batch ($(head -1 <<<"$out" | cut -d' ' -f1))"; PASS=$((PASS+1))
        else
            echo "  FAIL $cb K=$K ${k}x$n batch $batch ($be):"; sed 's/^/    /' <<<"$out" | head -6; FAIL=$((FAIL+1))
        fi
    done
done <<'CASES'
256 384 2 3inst 3
256 384 4 3inst 1
256 384 2 mcg 2
256 384 3 mcg 5
256 384 4 mcg 1
256 384 8 mcg 2
256 384 1 mul1 2
256 384 3 mul1 4
256 384 5 mul1 1
256 384 2.5 mul1 3
6144 2048 3 mcg 1
2048 6144 3 mcg 1
6144 2048 5 mul1 2
6144 576 5 mul1 3
200 300 4 mcg 2
CASES

echo "[3/3] a real one: GLM-5.3's layer-0 kv_a_proj (net-gated)"
# fiore-lab's GLM-5.3 EXL3 checkpoint, one tensor group fetched by range
# request: MUL1 5 bits, 6144 → 576 outputs stored as 640
if [ "${NURL_NET_TESTS:-0}" = 1 ]; then
    f="$WORK/real.safetensors"
    if "$PY" tests/exl3_real.py "$EX" "https://huggingface.co/fiore-lab/GLM-5.3-EXL3-Base/resolve/main/nonexperts-5bit.safetensors" \
            model.layers.0.self_attn.kv_a_proj_with_mqa 576 "$f" 2 7 > "$WORK/real.log" 2>&1; then
        for be in $backends; do
            if [ "$be" = cpu ]; then out=$(NURL_GPU=cpu EXL3_FIXTURE="$f" "$WORK/exl3_test" 2>&1); rc=$?
            else out=$(EXL3_FIXTURE="$f" "$WORK/exl3_test" 2>&1); rc=$?; fi
            if [ "$rc" = 0 ] && [ "$(grep -c '^  PASS' <<<"$out")" = 2 ]; then
                echo "  PASS $(head -1 "$WORK/real.log") ($(head -1 <<<"$out" | cut -d' ' -f1))"; PASS=$((PASS+1))
            else echo "  FAIL the real tensor ($be):"; sed 's/^/    /' <<<"$out" | head -6; FAIL=$((FAIL+1)); fi
        done
    else
        echo "  SKIP the fetch failed: $(tail -1 "$WORK/real.log")"
    fi
else
    echo "  SKIP (NURL_NET_TESTS=1)"
fi

echo "== nurllama exl3 tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
