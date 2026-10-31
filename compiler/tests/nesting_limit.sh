#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/nesting_limit.sh — `--max-nesting` / NURL_MAX_NESTING /
#  `--max-nesting-fixed` (Agora #207).
#
#  gen_expr, gen_stmt and parse_type recurse once per level of nesting,
#  so a program nested deep enough ran nurlc out of stack: SIGSEGV, no
#  diagnostic. Past the limit the compile now stops with one. The flag
#  wins over the variable, 0 turns the limit off, and a fixed limit (what
#  nurlapi passes) is not raised by anything after it.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
[ -x "$NURLC" ] || { echo "nesting_limit: $NURLC not found — run ./build.sh" >&2; exit 2; }

# GNU timeout, or Homebrew's gtimeout on macOS (as test_harness.sh picks).
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD=gtimeout
else echo "nesting_limit: needs timeout (on macOS: brew install coreutils)" >&2; exit 2; fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-60s %s\n' "$1" "$2"; }
ok() { note "$1" "ok"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

# rep <n> <text> — <text> n times.
rep() { local i; for ((i = 0; i < $1; i++)); do printf '%s' "$2"; done; }
# chain <n> — main returns a chain of n binary operators: n levels.
chain() { { printf '@ main → i {\n^ '; rep "$1" '+ 1 '; printf '0\n}\n'; } > "$WORK/p.nu"; }

# run <label> <expect: ok|reject|usage> [env…] -- [nurlc args…]
# Runs nurlc on p.nu. A rejection must be exit 1, never a crash.
run() {
    local label="$1" want="$2"; shift 2
    local envs=()
    while [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    # ${envs[@]+…}: an empty array under `set -u` is "unbound" to bash 3.2
    # (macOS's /bin/bash), which aborted the script there.
    "$TIMEOUT_CMD" 60 env ${envs[@]+"${envs[@]}"} "$NURLC" "$@" "$WORK/p.nu" > /dev/null 2> "$WORK/err"
    local rc=$?
    case "$want" in
        ok) [ $rc -eq 0 ] && ok "$label" || bad "$label" "rc=$rc: $(head -1 "$WORK/err")" ;;
        reject) [ $rc -eq 1 ] && ok "$label" || bad "$label" "rc=$rc (want 1): $(head -1 "$WORK/err")" ;;
        usage) [ $rc -eq 2 ] && ok "$label" || bad "$label" "rc=$rc (want 2)" ;;
    esac
}
says() {  # says <label> <fixed string> — the last run's stderr has it
    grep -qF -- "$2" "$WORK/err" && ok "$1" || bad "$1" "stderr: $(head -1 "$WORK/err")"
}
says_not() {
    grep -qF -- "$2" "$WORK/err" && bad "$1" "stderr has '$2'" || ok "$1"
}

chain 5
run "shallow program under a low limit"        ok     -- --max-nesting=50
chain 40
run "past --max-nesting"                       reject -- --max-nesting=20
says "  names the limit"                       "nested deeper than 20 levels"
says "  says how to raise it"                  "--max-nesting=N or NURL_MAX_NESTING=N"
run "past NURL_MAX_NESTING"                    reject NURL_MAX_NESTING=20 --
run "the flag wins over the variable"          ok     NURL_MAX_NESTING=20 -- --max-nesting=500

chain 1100
run "the default limit (1000)"                 reject --
says "  names the default"                     "nested deeper than 1000 levels"
run "--max-nesting=0 turns it off"             ok     -- --max-nesting=0
run "NURL_MAX_NESTING=0 turns it off"          ok     NURL_MAX_NESTING=0 --

chain 40
run "--max-nesting-fixed"                      reject -- --max-nesting-fixed=20
says "  says it cannot be raised"              "it cannot be raised here"
says_not "  offers no flag that will not work" "--max-nesting=N"
run "a later --max-nesting does not raise it"  reject -- --max-nesting-fixed=20 --max-nesting=500
run "a later --max-nesting-fixed does not either" reject -- --max-nesting-fixed=20 --max-nesting-fixed=500
run "nor does NURL_MAX_NESTING"                reject NURL_MAX_NESTING=500 -- --max-nesting-fixed=20

run "--max-nesting=abc refuses to start"       usage  -- --max-nesting=abc
run "--max-nesting=-5 refuses to start"        usage  -- --max-nesting=-5
run "--max-nesting= refuses to start"          usage  -- --max-nesting=
run "NURL_MAX_NESTING=x refuses to start"      usage  NURL_MAX_NESTING=x --

# Each shape that used to overflow the stack, 60000 deep: a diagnostic.
{ printf '@ main → i {\n'; rep 60000 '{ '; printf ': i z 1'; rep 60000 ' }'; printf '\n^ 0\n}\n'; } > "$WORK/p.nu"
run "60000 nested blocks: a diagnostic, not a crash" reject --
{ printf '@ main → i {\n'; rep 60000 '? T { '; printf ': i z 1'; rep 60000 ' } {}'; printf '\n^ 0\n}\n'; } > "$WORK/p.nu"
run "60000 nested conditionals"                reject --
{ printf '@ id i x → i { ^ x }\n@ main → i {\n^ '; rep 60000 '( id '; printf '0'; rep 60000 ' )'; printf '\n}\n'; } > "$WORK/p.nu"
run "60000 nested calls"                       reject --
chain 60000
run "a chain of 60000 operators"               reject --
{ printf '@ main → i {\n: '; rep 60000 '*'; printf 'u p # *u 0\n^ 0\n}\n'; } > "$WORK/p.nu"
run "a type 60000 pointers deep"               reject --
says "  types count too"                       "nested deeper than 1000 levels"

# A diagnostic deep inside one declaration unwinds past the count; the
# next declaration must start from zero, not from where the first broke.
{ printf '@ f → i {\n^ '; rep 15 '+ 1 '; printf 'nope\n}\n@ main → i {\n^ '; rep 15 '+ 1 '; printf '0\n}\n'; } > "$WORK/p.nu"
run "an error deep in one declaration"         reject -- --max-nesting=25
says "  is reported"                           "nope"
says_not "  and leaves the next one's count alone" "nested deeper"

if [ "$fails" -eq 0 ]; then echo "nesting_limit: all assertions hold"; exit 0; fi
echo "nesting_limit: $fails assertion(s) FAILED"; exit 1
