#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/dsa_select_test.sh — lk_dsa_select keeps exactly the keys the
#  counting rule keeps (fewer than topk keys beat it; ties to the lower
#  index), on random scores from widely spread down to one distinct value,
#  at npos below, at and above topk, one position and a batch (Agora #522).
#  Runs tests/dsa_select_test.nu on the CPU backend and, when there is one,
#  the GPU, and prints the time a launch takes at npos 4k..32k.
#
#  Needs nothing outside the repository.
#
#  Run from the package dir:  ./tests/dsa_select_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-dsa.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

for d in gguf safetensor tokenizer gpu http grad nn gpukit tensor hub nurldb; do
    [ -e "deps/$d" ] || { mkdir -p deps && ln -s "../../$d" "deps/$d"; }
done

echo "[1/2] build the selection test"
if ! $NURL tests/dsa_select_test.nu "$WORK/dsa" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tests/dsa_select_test.nu:"; tail -5 "$WORK/build.err"; exit 1
fi

echo "[2/2] every case against the counting rule"
backends="cpu"
[ "${NURL_GPU:-}" != cpu ] && backends="cpu default"
for be in $backends; do
    if [ "$be" = cpu ]; then out=$(NURL_GPU=cpu "$WORK/dsa" 2>&1); rc=$?; else out=$("$WORK/dsa" 2>&1); rc=$?; fi
    echo "$out" | sed 's/^/    /'
    if [ $rc -eq 0 ] && grep -q "of 24 cases as the rule" <<<"$out" && grep -q "selections: 24 of 24" <<<"$out"; then
        echo "  PASS $be"; PASS=$((PASS+1))
    else
        echo "  FAIL $be (exit $rc)"; FAIL=$((FAIL+1))
    fi
done
echo "== dsa_select tests: PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
