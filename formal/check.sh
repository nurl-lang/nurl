#!/bin/bash
# formal/check.sh — build the proof and check it is complete:
#   * every module builds;
#   * no `sorry`, `admit` or new `axiom` in the sources;
#   * the main theorems rest only on Lean's standard axioms.
set -euo pipefail
cd "$(dirname "$0")"
lake build
if grep -rnwE --include='*.lean' 'sorry|admit|axiom' A1 A1.lean A2 A2.lean A3 A3.lean; then
  echo "error: the proof is incomplete or adds an axiom" >&2; exit 1
fi
out=$(lake env lean Check.lean)
echo "$out"
bad=$(grep -oE "depends on axioms: \[[^]]*\]" <<<"$out" | grep -vE "^depends on axioms: \[(propext|Classical.choice|Quot.sound)(, (propext|Classical.choice|Quot.sound))*\]$" || true)
if [ -n "$bad" ] || ! grep -q "depends on axioms" <<<"$out"; then
  echo "error: unexpected axioms: $bad" >&2; exit 1
fi
echo "formal: A1, A2 and A3.0 proofs complete"
