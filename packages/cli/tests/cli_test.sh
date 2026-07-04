#!/usr/bin/env bash
# ============================================================
#  tests/cli_test.sh — build tests/demo.nu (a multi-command CLI built
#  with the facade) and drive every surface: subcommand routing, typed
#  flags with env + defaults + precedence, positionals, stdin, prompts,
#  help/version, unknown-command and no-command exit codes. Re-runs the
#  allocating paths under AddressSanitizer.
#
#  Run from the package dir:  ./tests/cli_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t cli-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got '$2', want '$3')"; }

echo "[1/3] build tests/demo.nu"
if ! $NURL tests/demo.nu "$WORK/demo" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build demo:"; tail -8 "$WORK/build.err"; exit 1
fi
D="$WORK/demo"

echo "[2/3] drive the facade"
eq "default flag value"  "$($D hello)"                 "hello, world"
eq "flag override"       "$($D hello --name Tero)"     "hello, Tero"
eq "bool flag"           "$($D hello -n T --loud)"     "hello, T!"
eq "env fallback"        "$(DEMO_NAME=E $D hello)"      "hello, E"
eq "flag beats env"      "$(DEMO_NAME=E $D hello -n F)" "hello, F"
eq "positional sum"      "$($D add 3 4 5)"              "12"
eq "empty positionals"   "$($D add)"                   "0"
eq "int flag default"    "$($D port)"                  "port=8080"
eq "int flag override"   "$($D port --port 9000)"      "port=9000"
eq "int flag env"        "$(DEMO_PORT=7000 $D port)"   "port=7000"
eq "stdin slurp"         "$(printf hello | $D wc)"      "bytes=5"
eq "version"             "$($D --version)"             "demo 1.0.0"
eq "prompt confirm yes"  "$(printf 'y\n' | $D rm foo)"  "deleted foo"
eq "prompt confirm no"   "$(printf 'n\n' | $D rm foo)"  "aborted"

# exit codes
$D bogus  >/dev/null 2>&1; [ $? = 2 ] && ok "unknown command → 2"    || bad "unknown command exit"
$D        >/dev/null 2>&1; [ $? = 1 ] && ok "no command → 1"         || bad "no command exit"
$D hello  >/dev/null 2>&1; [ $? = 0 ] && ok "valid command → 0"      || bad "valid command exit"
$D --help >/dev/null 2>&1; [ $? = 0 ] && ok "--help → 0"             || bad "--help exit"
$D --help | grep -q "COMMANDS" && ok "help lists commands"          || bad "help commands"
$D hello --help | grep -q "print a greeting" && ok "command help"   || bad "command help"

echo "[3/3] AddressSanitizer"
if NURL_SAN=1 $NURL tests/demo.nu "$WORK/demo_san" >/dev/null 2>"$WORK/san_build.err"; then
    SAN_ERR=0
    for run in "add 3 4 5" "hello -n x --loud" "port --port 9" "--help" "hello --help" "bogus"; do
        printf 'y\n' | $WORK/demo_san $run >/dev/null 2>>"$WORK/san.out" || true
    done
    printf 'data' | $WORK/demo_san wc >/dev/null 2>>"$WORK/san.out" || true
    if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out" 2>/dev/null; then
        bad "ASan clean"; grep -m3 "ERROR\|leak" "$WORK/san.out"
    else
        ok "ASan clean (no errors, no leaks)"
    fi
else
    echo "  (skipped ASan build)"
fi

echo "== cli tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
