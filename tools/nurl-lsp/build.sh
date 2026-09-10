#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build
# A failed rebuild must not leave an older server posing as the result.
rm -f build/nurl-lsp
exec "$ROOT_DIR/nurl.sh" -O2 tools/nurl-lsp/main.nu "$ROOT_DIR/build/nurl-lsp"
