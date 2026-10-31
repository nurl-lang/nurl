#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  packages/nurl-mcp/tests/stdio_test.sh — nurl-mcp end to end over
#  stdio, against THIS checkout's toolchain (build/nurlc, nurl.sh,
#  build/nurlfmt, stdlib/, docs/, formal/).
#
#  What an agent sees, checked as it sees it: inline source is named by
#  `filename` in every diagnostic (never a temp path), the borrow checker
#  reports a column, nurl_check / nurl_build / nurl_run / nurl_fmt work on
#  inline source, nurl_docs serves formal/ and its probe table, nurl_api
#  answers a query, and nothing is left in $TMPDIR.
#
#  Run from the repo root after ./build.sh:
#      ./packages/nurl-mcp/tests/stdio_test.sh
#  No network needed (no package= or registry calls).
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The package's deps, as nurlpkg would lay them out.
mkdir -p packages/nurl-mcp/deps
ln -sfn ../../wasmbuilder packages/nurl-mcp/deps/wasmbuilder
( cd packages/nurl-mcp && NURL_STDLIB="$ROOT" "$ROOT/nurl.sh" src/main.nu "$WORK/nurl-mcp" >/dev/null )

# The toolchain on PATH as an install puts it: nurl, nurlc, nurlfmt.
mkdir -p "$WORK/bin" "$WORK/tmp"
printf '#!/bin/sh\nexec "%s/nurl.sh" "$@"\n' "$ROOT" > "$WORK/bin/nurl"
chmod +x "$WORK/bin/nurl"
ln -s "$ROOT/build/nurlc" "$WORK/bin/nurlc"
ln -s "$ROOT/build/nurlfmt" "$WORK/bin/nurlfmt"

PATH="$WORK/bin:$PATH" NURL_STDLIB="$ROOT" NURL_DOCS="$ROOT/docs" TMPDIR="$WORK/tmp" \
python3 - "$WORK/nurl-mcp" <<'PY'
import json, os, subprocess, sys
srv = sys.argv[1]
UAM = ("$ `stdlib/core/vec.nu`\n@ main → i {\n    : ( Vec i ) v ( vec_new [i] )\n"
       "    : ( @ i ) f \\ → i { ^ ( vec_len [i] v ) }\n    ( vec_free [i] v )\n"
       "    ( nurl_println_int ( f ) )\n    ^ 0\n}\n")
calls = [
    ("nurl_check", {"source": UAM, "filename": "uam.nu"}),
    ("nurl_build", {"source": "@ main → i { ^ + 1 }\n", "filename": "short.nu"}),
    ("nurl_run", {"source": "@ main → i {\n    ( nurl_println `hi-from-mcp` )\n    ^ 3\n}\n"}),
    ("nurl_fmt", {"source": "@ main → i {  ^ 0 }\n"}),
    ("nurl_docs", {"name": "formal/corpus/map.tsv", "query": "h274"}),
    ("nurl_docs", {"name": "../formal/RULES.md", "outline": True}),
    ("nurl_api", {"module": "core/vec.nu"}),
    ("nurl_read_stdlib", {"name": "core/string.nu"}),
    ("nurl_list_stdlib", {}),
    ("nurl_api", {"query": "vec push"}),
]
msgs = [{"jsonrpc": "2.0", "id": 0, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}}]
msgs += [{"jsonrpc": "2.0", "id": i + 1, "method": "tools/call", "params": {"name": n, "arguments": a}}
         for i, (n, a) in enumerate(calls)]
p = subprocess.run([srv, "--allow-run"], input="".join(json.dumps(m) + "\n" for m in msgs).encode(),
                   capture_output=True, timeout=600)
res = {}
for line in p.stdout.decode().splitlines():
    j = json.loads(line)
    if j.get("id"):
        r = j.get("result", {})
        res[j["id"]] = (r.get("isError"), "".join(c.get("text", "") for c in r.get("content", [])))
fails = []
def check(name, cond, got=""):
    print(("  PASS " if cond else "  FAIL ") + name)
    if not cond:
        fails.append(name + ": " + got[:300])
e, t = res.get(1, (None, ""))
check("check: borrowck error named by filename, with a column", e is True and "\nuam.nu:6:5: error: use of moved value 'v'" in "\n" + t.split("\n", 1)[1], t)
check("check: no temp path in diagnostics", "nurl-mcp-" not in t and "/tmp" not in t, t)
e, t = res.get(2, (None, ""))
check("build: front-end error named by filename", e is True and "short.nu:1:" in t, t)
check("build: no temp source path", ".nu:" not in t.replace("short.nu:", ""), t)
e, t = res.get(3, (None, ""))
check("run: inline source builds and runs", e is not True and "hi-from-mcp" in t and "[exit 3]" in t, t)
e, t = res.get(4, (None, ""))
check("fmt: canonical form", e is not True and "@ main → i { ^ 0 }" in t, t)
e, t = res.get(5, (None, ""))
# A probe named before Agora #212 is still found by its old id.
check("docs: probe table row", "old_id=h274" in t and "probe=closure_view_beside_growing_closure" in t and "nurlc=" in t, t)
e, t = res.get(6, (None, ""))
check("docs: the docs' ../formal/ link resolves", e is not True and t.startswith("formal/RULES.md"), t)
e, t = res.get(7, (None, ""))
check("api: module surface", e is not True and "vec_push" in t, t)
e, t = res.get(8, (None, ""))
check("read_stdlib: core/string.nu", e is not True and "@ string_new" in t, t)
e, t = res.get(9, (None, ""))
try:
    paths = [o["path"] for o in json.loads(t)]
except Exception:
    paths = []
check("list_stdlib: paths relative to the stdlib root", "core/vec.nu" in paths, t[:200])
e, t = res.get(10, (None, ""))
check("api: query finds vec_push in core/vec.nu", e is not True and "core/vec.nu" in t and "vec_push" in t, t)
left = os.listdir(os.environ["TMPDIR"])
check("nothing left in TMPDIR", not left, repr(left))
if fails:
    print("\n".join(fails))
    sys.exit(1)
print("nurl-mcp stdio: all checks passed")
PY
