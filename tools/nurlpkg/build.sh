#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Build with the same driver/ABI/sanitizer policy as every NURL program.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build
# A failed rebuild must not leave an old executable looking freshly built.
rm -f "build/nurlpkg"
exec "$ROOT_DIR/nurl.sh" -O2 "tools/nurlpkg/main.nu" "$ROOT_DIR/build/nurlpkg"
