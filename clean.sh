#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# Clean build artifacts from both build/ directory and legacy locations

echo "Cleaning NURL build artifacts..."

# Clean build directory
if [ -d "build" ]; then
    echo "  Cleaning build/ directory..."
    rm -rf build/*
fi

# Clean legacy artifacts from root directory
echo "  Cleaning legacy artifacts from root directory..."
rm -f *.ll
rm -f nurlc nurlc.exe
rm -f nurlc_py* nurlc_self*
rm -f *.tmp

# Clean Python cache
echo "  Cleaning Python cache..."
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

echo "Clean complete!"