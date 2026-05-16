#!/usr/bin/env bash
# compare/run_bench.sh — reproducible CSV benchmark harness.
#
# Runs ./nurl_analysis and ./.venv/bin/python polars_analysis.py
# N times each, parses their stage timings, reports min/median per
# stage, and appends one block to compare/HISTORY.md.
#
# `nurl_analysis` runs the unified `csv_table_*` pipeline (arena
# layout is now the stdlib default; the legacy `CSVTable v1 path`
# / `nurl_analysis_arena.exe` split is gone — both files compiled
# the same parser after the consolidation).
#
# Usage:  ./run_bench.sh [N]            # default 5
#         ./run_bench.sh --no-history   # skip HISTORY.md append
#         ./run_bench.sh --label "phase1-indexed-sort"
#
# Re-run between two no-op commits and confirm variance < 3 % on
# every stage before claiming a phase is gated.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

N=5
APPEND_HISTORY=1
LABEL=""
BINARY="nurl_analysis"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-history)  APPEND_HISTORY=0; shift ;;
        --label)       LABEL="$2"; shift 2 ;;
        --label=*)     LABEL="${1#--label=}"; shift ;;
        [0-9]*)        N="$1"; shift ;;
        *)             echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

PY="$SCRIPT_DIR/.venv/bin/python"
NURL_BIN="$SCRIPT_DIR/$BINARY"
DATA="$SCRIPT_DIR/test_data.csv"

[[ -x "$NURL_BIN" ]] || { echo "missing $NURL_BIN — build with ../nurl.sh $BINARY.nu $BINARY" >&2; exit 1; }
[[ -x "$PY"       ]] || { echo "missing $PY — create venv and pip install polars" >&2; exit 1; }
[[ -s "$DATA"     ]] || { echo "missing $DATA — run: $PY generate_data.py" >&2; exit 1; }

DATA_SHA=$(sha256sum "$DATA" | awk '{print $1}')
DATA_BYTES=$(stat -c '%s' "$DATA")

# ── helpers ──────────────────────────────────────────────────────────
median()  { awk '{print $0}' | sort -n | awk 'BEGIN{c=0} {a[c++]=$0} END{ if(c==0){print 0;exit} if(c%2)print a[(c-1)/2]; else printf "%.0f\n", (a[c/2-1]+a[c/2])/2 }'; }
min_val() { awk 'NR==1||$1<m{m=$1} END{print m+0}'; }

extract_nurl_stage() {  # $1=stage_label, reads stdin
    awk -v stage="$1" '
        $0 ~ stage" "       { for(i=1;i<=NF;i++) if($i ~ /ms$/){gsub(/ms$/,"",$i); print $i; exit} }
        $0 ~ "^"stage" to " { for(i=1;i<=NF;i++) if($i ~ /ms$/){gsub(/ms$/,"",$i); print $i; exit} }
    '
}

run_nurl() {
    "$NURL_BIN" 2>/dev/null
}

run_polars() {
    "$PY" polars_analysis.py 2>/dev/null
}

declare -a NURL_LOAD NURL_FILT NURL_SORT NURL_WRITE NURL_TOTAL
declare -a POL_LOAD  POL_FILT  POL_SORT  POL_WRITE  POL_TOTAL

echo "Running NURL ${N}× …"
for ((i=1; i<=N; i++)); do
    out="$(run_nurl)"
    NURL_LOAD+=( "$(echo "$out" | awk '/^Loaded /  {gsub(/ms$/,"",$NF);print $NF}')" )
    NURL_FILT+=( "$(echo "$out" | awk '/^Filtered/  {gsub(/ms$/,"",$NF);print $NF}')" )
    NURL_SORT+=( "$(echo "$out" | awk '/^Sorted /  {gsub(/ms$/,"",$NF);print $NF}')" )
    NURL_WRITE+=( "$(echo "$out" | awk '/^Top-10 /  {gsub(/ms$/,"",$NF);print $NF}')" )
    NURL_TOTAL+=( "$(echo "$out" | awk '/^Total: / {gsub(/ms$/,"",$NF);print $NF}')" )
    printf "  run %d: load=%sms filter=%sms sort=%sms write=%sms total=%sms\n" \
        "$i" "${NURL_LOAD[-1]}" "${NURL_FILT[-1]}" "${NURL_SORT[-1]}" "${NURL_WRITE[-1]}" "${NURL_TOTAL[-1]}"
done

echo "Running Polars ${N}× …"
for ((i=1; i<=N; i++)); do
    out="$(run_polars)"
    POL_LOAD+=( "$(echo "$out" | awk '/^Loaded /  {gsub(/ms$/,"",$NF);print $NF}')" )
    POL_FILT+=( "$(echo "$out" | awk '/^Filtered/  {gsub(/ms$/,"",$NF);print $NF}')" )
    POL_SORT+=( "$(echo "$out" | awk '/^Sorted /  {gsub(/ms$/,"",$NF);print $NF}')" )
    POL_WRITE+=( "$(echo "$out" | awk '/^Top-10 /  {gsub(/ms$/,"",$NF);print $NF}')" )
    POL_TOTAL+=( "$(echo "$out" | awk '/^Total: / {gsub(/ms$/,"",$NF);print $NF}')" )
    printf "  run %d: load=%sms filter=%sms sort=%sms write=%sms total=%sms\n" \
        "$i" "${POL_LOAD[-1]}" "${POL_FILT[-1]}" "${POL_SORT[-1]}" "${POL_WRITE[-1]}" "${POL_TOTAL[-1]}"
done

stat_block() {
    local name="$1"; shift
    local arr=( "$@" )
    local mn md
    mn=$(printf '%s\n' "${arr[@]}" | min_val)
    md=$(printf '%s\n' "${arr[@]}" | median)
    printf "%-7s min=%5sms  median=%5sms\n" "$name" "$mn" "$md"
}

echo
echo "── NURL ──────────────────────────────────────"
stat_block "load"   "${NURL_LOAD[@]}"
stat_block "filter" "${NURL_FILT[@]}"
stat_block "sort"   "${NURL_SORT[@]}"
stat_block "write"  "${NURL_WRITE[@]}"
stat_block "total"  "${NURL_TOTAL[@]}"

echo
echo "── Polars ────────────────────────────────────"
stat_block "load"   "${POL_LOAD[@]}"
stat_block "filter" "${POL_FILT[@]}"
stat_block "sort"   "${POL_SORT[@]}"
stat_block "write"  "${POL_WRITE[@]}"
stat_block "total"  "${POL_TOTAL[@]}"

# ── HISTORY.md append ────────────────────────────────────────────────
if (( APPEND_HISTORY )); then
    HISTORY="$SCRIPT_DIR/HISTORY.md"
    DATE=$(date -u +"%Y-%m-%d %H:%M:%SZ")
    SHA=$(cd "$SCRIPT_DIR/.." && git rev-parse --short HEAD 2>/dev/null || echo "no-git")
    DIRTY=$(cd "$SCRIPT_DIR/.." && git diff --quiet 2>/dev/null && echo "" || echo "+dirty")
    UNAME=$(uname -srm)
    CPU=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo unknown)

    nurl_med() { printf '%s\n' "$@" | median; }
    {
        echo
        echo "## ${DATE} — ${SHA}${DIRTY}${LABEL:+ — $LABEL}"
        echo "- CPU: $CPU"
        echo "- Kernel: $UNAME"
        echo "- Fixture: test_data.csv (1 M rows × 8 cols, ${DATA_BYTES} B, sha256=${DATA_SHA:0:16}…)"
        echo "- Runs: ${N} per implementation"
        echo
        echo "| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |"
        echo "|--------|---------:|---------:|-----------:|-----------:|------------------:|"
        for stage in load filter sort write total; do
            case "$stage" in
                load)   na=("${NURL_LOAD[@]}");  pa=("${POL_LOAD[@]}");  ;;
                filter) na=("${NURL_FILT[@]}");  pa=("${POL_FILT[@]}");  ;;
                sort)   na=("${NURL_SORT[@]}");  pa=("${POL_SORT[@]}");  ;;
                write)  na=("${NURL_WRITE[@]}"); pa=("${POL_WRITE[@]}"); ;;
                total)  na=("${NURL_TOTAL[@]}"); pa=("${POL_TOTAL[@]}"); ;;
            esac
            nm=$(printf '%s\n' "${na[@]}" | min_val)
            nme=$(printf '%s\n' "${na[@]}" | median)
            pm=$(printf '%s\n' "${pa[@]}" | min_val)
            pme=$(printf '%s\n' "${pa[@]}" | median)
            ratio="—"
            if [[ "$pme" -gt 0 ]] 2>/dev/null; then
                ratio=$(awk -v n="$nme" -v p="$pme" 'BEGIN{printf "%.1f×", n/p}')
            fi
            printf "| %-6s | %8s | %8s | %10s | %10s | %17s |\n" "$stage" "$nm" "$nme" "$pm" "$pme" "$ratio"
        done
    } >> "$HISTORY"
    echo
    echo "Appended block to $HISTORY"
fi
