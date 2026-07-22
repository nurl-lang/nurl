#!/usr/bin/env bash
# packages/grad/tests/emitc_oracle.sh — the C oracle for the CUDA-C grad()
# emitter. emitc_dump builds a scalar loss touching every supported op,
# prints the emitted device function, the tape's parameter gradients (f64
# bits) and the probe inputs. This script compiles the emitted C on the
# HOST (gcc, -O2 -ffp-contract=off — one IEEE rounding per written op,
# same as the tape) with a stub swarm_g_add and asserts the C gradients
# equal the tape's BIT FOR BIT. Skips without a C compiler.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export NURL_STDLIB="$REPO"
command -v cc >/dev/null || { echo "[emitc-oracle] SKIP — no C compiler"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

( cd "$HERE" && "$REPO/nurl.sh" tests/emitc_dump.nu "$TMP/dump" >/dev/null 2>&1 ) \
    || { echo "[emitc-oracle] FAIL build"; ( cd "$HERE" && "$REPO/nurl.sh" tests/emitc_dump.nu "$TMP/dump" 2>&1 | tail -5 ); exit 1; }
"$TMP/dump" > "$TMP/out.txt" || { echo "[emitc-oracle] FAIL dump"; exit 1; }

awk '/===SRC===/{f=1;next}/===GRADS===/{f=0}f' "$TMP/out.txt" > "$TMP/grad.c.in"
awk '/===GRADS===/{f=1;next}/===PROBE===/{f=0}f' "$TMP/out.txt" > "$TMP/grads.txt"
awk '/===PROBE===/{f=1;next}f' "$TMP/out.txt" > "$TMP/probe.txt"

# host build: __device__ → nothing, stub swarm_g_add collects into g[]
{
  echo '#include <math.h>'
  echo '#include <stdio.h>'
  echo '#include <stdint.h>'
  echo '#include <string.h>'
  echo 'static void swarm_g_add(double* g, int j, double val) { g[j] += val; }'
  sed 's/__device__ //' "$TMP/grad.c.in"
  cat <<'CMAIN'
int main(int argc, char** argv) {
  double pr[5]; // x v p0 p1 p2 (x arrives as a double bit pattern too)
  for (int i = 0; i < 5; i++) { long long b; sscanf(argv[1+i], "%lld", &b); memcpy(&pr[i], &b, 8); }
  long long x = (long long)pr[0];
  double v = pr[1];
  double p[3] = { pr[2], pr[3], pr[4] };
  double g[3] = { 0.0, 0.0, 0.0 };
  grad(x, v, g, p);
  for (int j = 0; j < 3; j++) { long long b; memcpy(&b, &g[j], 8); printf("%lld\n", b); }
  return 0;
}
CMAIN
} > "$TMP/harness.c"

cc -O2 -ffp-contract=off -o "$TMP/harness" "$TMP/harness.c" -lm \
    || { echo "[emitc-oracle] FAIL cc (emitted C does not compile)"; sed -n '1,40p' "$TMP/harness.c"; exit 1; }

mapfile -t PROBE < "$TMP/probe.txt"
"$TMP/harness" "${PROBE[@]}" > "$TMP/cgrads.txt"

if diff -q "$TMP/grads.txt" "$TMP/cgrads.txt" >/dev/null; then
  echo "[emitc-oracle] PASS — emitted C gradients BIT-EQUAL to the tape (3 params, every scalar op)"
  exit 0
else
  echo "[emitc-oracle] FAIL — gradients differ:"
  paste "$TMP/grads.txt" "$TMP/cgrads.txt"
  exit 1
fi
