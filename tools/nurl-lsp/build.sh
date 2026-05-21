#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Compatibility wrapper. The canonical entrypoint is now `zig build nurl-lsp`.

set -euo pipefail
exec zig build nurl-lsp
