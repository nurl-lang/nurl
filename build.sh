#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Compatibility wrapper. The canonical entrypoint is now `zig build`.

set -euo pipefail

RUN_TESTS=1
SAN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-tests) RUN_TESTS=0; shift ;;
        --san) SAN=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ $SAN -eq 1 ]]; then
    if [[ $RUN_TESTS -eq 1 ]]; then
        exec zig build -Dsan=true
    else
        exec zig build -Dsan=true
    fi
fi

if [[ $RUN_TESTS -eq 1 ]]; then
    exec zig build check
fi

exec zig build
