#!/usr/bin/env bash
# Differential fuzz for nwasm: random wasm modules (wasm-tools smith),
# every no-param exported function invoked under nwasm JIT / JIT-nopin /
# interpreter and the reference wasmtime.
#
#   tests/fuzz_diff.sh <nwasm-binary> [N-modules] [first-seed]
#
# Result classes must agree everywhere (value vs trap); exact values are
# compared for all-integer signatures (float formatting and trap message
# text are engine-specific). Modules that reproduce a divergence are
# saved next to the work dir as bad_<seed>_<fn>.wasm / ref_<seed>_<fn>.wasm.
# Needs: wasm-tools (smith/print), wasmtime, python3.
set -u
NW=${1:?usage: fuzz_diff.sh <nwasm-binary> [N] [seed0]}
N=${2:-200}
SEED0=${3:-1}
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${FUZZ_WORK:-$(mktemp -d)}
mkdir -p "$WORK"
fail=0
nmod=0
ninv=0
nval=0
for ((i=0;i<N;i++)); do
  seed=$((SEED0+i))
  python3 -c "import random,sys; random.seed($seed); sys.stdout.buffer.write(bytes(random.getrandbits(8) for _ in range(4096)))" > "$WORK/rnd.bin"
  wasm-tools smith --ensure-termination --fuel 1000 --bulk-memory-enabled true --saturating-float-to-int-enabled true --sign-extension-ops-enabled true \
    --min-funcs 3 --max-imports 0 --export-everything true --max-memories 1 --max-tables 1 --threads-enabled false \
    --gc-enabled false --simd-enabled false --relaxed-simd-enabled false --exceptions-enabled false --tail-call-enabled false \
    --memory64-enabled false --custom-page-sizes-enabled false --wide-arithmetic-enabled false --extended-const-enabled false \
    "$WORK/rnd.bin" -o "$WORK/m.wasm" 2>/dev/null || continue
  nmod=$((nmod+1))
  while IFS=$'\t' read -r f flag; do
    [ "$flag" = N ] && continue
    [ -z "$f" ] && continue
    ref=$(timeout 10 wasmtime run -C cache=n -W trap-on-grow-failure=y --invoke "$f" "$WORK/m.wasm" 2>&1); rrc=$?
    a=$(timeout 10 "$NW" run --invoke "$f" "$WORK/m.wasm" 2>&1); arc=$?
    b=$(timeout 10 env NURL_NWASM_PIN=0 "$NW" run --invoke "$f" "$WORK/m.wasm" 2>&1); brc=$?
    c=$(timeout 10 env NURL_NWASM_JIT=0 "$NW" run --invoke "$f" "$WORK/m.wasm" 2>&1); crc=$?
    refv=$(grep -v '^warning:' <<<"$ref")
    cls() { if [ "$1" = 0 ]; then echo "V:$2"; else echo "T"; fi; }
    ca=$(cls $arc "$a"); cb=$(cls $brc "$b"); cc=$(cls $crc "$c")
    cr=$(cls $rrc "$refv")
    ninv=$((ninv+1)); [ "$arc" = 0 ] && nval=$((nval+1))
    if [ "$ca" != "$cb" ] || [ "$ca" != "$cc" ]; then
      echo "INTERNAL-DIVERGE seed=$seed f=$f jit=[$arc:$a] nopin=[$brc:$b] interp=[$crc:$c]"
      cp "$WORK/m.wasm" "$WORK/bad_${seed}_$f.wasm"; fail=1
    else
      ok=1
      an="$a"; [ "$an" = "(no result)" ] && an=""
      if [ "$arc" = 0 ] && [ "$rrc" = 0 ]; then
        if [ "$flag" = I ]; then [ "$an" = "$refv" ] || ok=0; fi
      else
        [ "$ca" = "$cr" ] || ok=0
      fi
      if [ "$ok" = 0 ]; then
        echo "REF-DIVERGE seed=$seed f=$f nwasm=[$arc:$a] ref=[$rrc:$refv]"
        cp "$WORK/m.wasm" "$WORK/ref_${seed}_$f.wasm"; fail=1
      fi
    fi
  done < <(python3 "$HERE/fuzz_sigs.py" "$WORK/m.wasm" 2>/dev/null | head -8)
done
echo "coverage: modules=$nmod invocations=$ninv value-returning=$nval (work dir: $WORK)"
[ $fail = 0 ] && [ $ninv -gt 0 ] && echo "FUZZ-CLEAN"
