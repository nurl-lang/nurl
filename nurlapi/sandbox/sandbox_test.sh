#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  nurlapi/sandbox/sandbox_test.sh — what nurl-sandbox lets a build tool
#  see (Agora #207).
#
#  Usage: nurlapi/sandbox/sandbox_test.sh [path/to/nurl-sandbox]
#  Without an argument the wrapper is compiled into a temp dir.
#
#  On a kernel without Landlock the confinement checks cannot run: the
#  test says so, checks that --require refuses to run anything, and
#  exits 0.
# ============================================================
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SB="${1:-}"
if [ -z "$SB" ]; then
    SB="$WORK/nurl-sandbox"
    cc -O2 -Wall -Wextra -Werror -std=c11 -o "$SB" "$ROOT/nurlapi/sandbox/nurl_sandbox.c" || exit 2
fi
fails=0
note() { printf '  %-58s %s\n' "$1" "$2"; }
ok() { note "$1" "ok"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }
yes() { local l="$1"; shift; "$@" >/dev/null 2>&1 && ok "$l" || bad "$l" "refused"; }
no() { local l="$1"; shift; "$@" >/dev/null 2>&1 && bad "$l" "allowed" || ok "$l"; }

# The tree a build sees: its own directory and nothing else of the
# server's. `other` stands in for another build's directory, `secret`
# for a file outside every allowed tree. Both live outside the default
# read-only list (under the temp dir), as /app does in the image.
mkdir -p "$WORK/build" "$WORK/other"
echo mine > "$WORK/build/in.txt"
echo theirs > "$WORK/other/in.txt"
echo secret > "$WORK/secret"
run() { "$SB" --require --rw="$WORK/build" -- "$@"; }

probe="$("$SB" --probe)"
echo "nurl-sandbox --probe: $probe"
case "$probe" in
    landlock*) ;;
    *)
        no "--require refuses to run unconfined" run true
        echo "sandbox_test: Landlock unavailable here — confinement not checked"
        exit 0 ;;
esac

yes "runs the tool"                                 run true
yes "reads its own build directory"                 run cat "$WORK/build/in.txt"
yes "writes its own build directory"                run sh -c "echo x > '$WORK/build/out.txt'"
yes "TMPDIR is its build directory"                 run sh -c "[ \"\$TMPDIR\" = '$WORK/build' ]"
yes "mktemp works there"                            run mktemp
yes "reads the system tree (/etc/hostname or /usr)" run sh -c 'cat /etc/hostname || ls /usr'
yes "writes /dev/null"                              run sh -c 'echo x > /dev/null'
no  "cannot read another build's directory"         run cat "$WORK/other/in.txt"
no  "cannot list it"                                run ls "$WORK/other"
no  "cannot read a file outside every tree"         run cat "$WORK/secret"
no  "cannot write outside its directory"            run sh -c "echo x > '$WORK/other/out.txt'"
no  "cannot write /etc"                             run sh -c 'echo x > /etc/nurl-sandbox-test'
no  "cannot write /tmp"                             run sh -c 'echo x > /tmp/nurl-sandbox-test.$$'
no  "a child of the tool is confined too"           run sh -c "sh -c 'cat $WORK/secret'"
yes "--ro adds a read-only tree"                    "$SB" --require --rw="$WORK/build" --ro="$WORK/other" -- cat "$WORK/other/in.txt"
no  "  and only read-only"                          "$SB" --require --rw="$WORK/build" --ro="$WORK/other" -- sh -c "echo x > '$WORK/other/out.txt'"
abi="${probe#landlock }"
if [ "$abi" -ge 4 ] && command -v python3 >/dev/null 2>&1; then
    # A listener outside the sandbox the tool must not reach.
    python3 -c 'import socket,time
s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(1)
open("'"$WORK"'/port","w").write(str(s.getsockname()[1])); time.sleep(20)' &
    lpid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$WORK/port" ] && break; sleep 0.2; done
    port="$(cat "$WORK/port" 2>/dev/null)"
    yes "the listener is reachable unconfined"      python3 -c "import socket; socket.create_connection(('127.0.0.1',$port),2)"
    no  "a TCP connect is refused (ABI 4+)"         run python3 -c "import socket; socket.create_connection(('127.0.0.1',$port),2)"
    kill "$lpid" 2>/dev/null
fi
if [ "$abi" -ge 6 ]; then
    sleep 30 & spid=$!
    no  "cannot signal a process outside (ABI 6+)"  run kill -0 "$spid"
    kill "$spid" 2>/dev/null
fi
"$SB" --rw="$WORK/build" -- /nonexistent/tool >/dev/null 2>&1
[ $? -eq 127 ] && ok "a missing tool is exit 127" || bad "a missing tool is exit 127" "other exit"

if [ "$fails" -eq 0 ]; then echo "sandbox_test: all assertions hold"; exit 0; fi
echo "sandbox_test: $fails assertion(s) FAILED"; exit 1
