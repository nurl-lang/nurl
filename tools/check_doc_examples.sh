#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  tools/check_doc_examples.sh — every NURL example in the docs
#  compiles, or is rejected with the diagnostic it says it shows.
#
#  Readers and agents copy documentation examples verbatim, and nothing
#  compiled them: MEMORY.md §2.11's closure example died with "unknown
#  generic type ( Vec … )" — it had no vec import — long before the
#  use-after-move it was written to demonstrate. The first run of this
#  gate found more than missing imports: operators called like
#  functions, /* */ comments the language does not have, FFI and raw
#  pointers in safe code, a `continue` that never advanced its counter,
#  quoted diagnostics the compiler no longer prints, and signatures that
#  had changed under the README quoting them.
#
#  Every ```nurl fence in docs/*.md, docs/stdlib/*.md, README.md and
#  the package READMEs is wrapped into a compilation unit (`main` around
#  a fragment; nothing imported implicitly) and run through
#  `nurlc --check`, the full frontend with no IR written, in parallel.
#  A fence annotated `expect-error="TEXT"` must be rejected with TEXT, so
#  the documented diagnostics are pinned too: a message reworded under a
#  doc that quotes it fails here. In docs/ and README.md an untagged
#  fence is an error, so no example opts out by omission. The fence
#  annotations are documented in tools/check_doc_examples.py and
#  docs/TOOLING.md.
#
#  Usage:
#    ./tools/check_doc_examples.sh                 # gate (all files)
#    ./tools/check_doc_examples.sh docs/MEMORY.md  # one file
#    ./tools/check_doc_examples.sh -v …            # also print each failing
#                                                  # block as compiled
#    NURL_DOCTEST_JOBS=N                           # parallel compiles (default
#                                                  # min(4, cores))
#
#  Exit codes:
#    0 — every block behaves as annotated
#    1 — a block failed, or a fence is malformed (listed as file:line)
#    2 — environment problem (no python3, build/nurlc not built)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || { echo "error: python3 not on PATH" >&2; exit 2; }

exec python3 "$SCRIPT_DIR/check_doc_examples.py" "$@"
