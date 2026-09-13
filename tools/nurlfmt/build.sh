#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Build with the same driver/ABI/sanitizer policy as every NURL program.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build
# The driver publishes atomically on success. A failed rebuild stays failed
# while preserving the last working tool for other invocations.
exec "$ROOT_DIR/nurl.sh" -O2 "tools/nurlfmt/nurlfmt.nu" "$ROOT_DIR/build/nurlfmt"
