#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  check_mingw_cross.sh — the Windows runtime must LINK against the
#  older msvcrt.dll, not just against UCRT.
#
#  There are two Windows toolchains in this project's life and only one
#  of them was ever under test:
#
#    * windows-tests.yml builds on a real windows-latest runner with the
#      LLVM clang (MSVC ABI, UCRT) and with a bundled zig, whose
#      windows-gnu target links zig's own mingw-w64 — also UCRT.
#    * nurlapi's /build_windows cross-compiles from Linux with the
#      DISTRO mingw-w64 (`gcc-mingw-w64-x86-64`), which defaults to
#      msvcrt.dll.
#
#  A UCRT-only CRT export therefore compiles, links and passes every
#  Windows gate while making the second toolchain fail on EVERY program,
#  hello world included — mingw links the whole runtime object, so the
#  undefined symbol has nothing to do with what the program called:
#
#      runtime.win.o:runtime.c:(.text$nurl_tz_offset+0x13):
#          undefined reference to `__imp__get_timezone'
#
#  That shipped in 0.54.0 (`_get_timezone`, added with `time_local`) and
#  survived two releases because no gate ran this toolchain. This one
#  does, in about ten seconds: compile the runtime translation unit for
#  mingw and link a trivial main against it. It needs no Windows, no
#  emulator and no NURL build — just the cross toolchain.
#
#  Usage:  tools/check_mingw_cross.sh
#  Exit:   0 = links (or toolchain absent, and it says so)
#          1 = the Windows runtime does not link on msvcrt
#          2 = setup error
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="${MINGW_CC:-x86_64-w64-mingw32-gcc}"
say() { echo "check_mingw_cross: $*"; }

if ! command -v "$CC" >/dev/null 2>&1; then
    # A missing toolchain is not a pass, and it must not read as one:
    # this gate exists because a silent skip is how the regression got
    # in. CI installs it; a developer box that has not is told what to
    # install rather than told "ok".
    say "SKIP — no $CC on PATH."
    say "      Install it to run this gate:  apt-get install gcc-mingw-w64-x86-64"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# stdlib/runtime.c is the single translation unit a Windows build links
# (it #includes the core and the FFI half); compiling it is what surfaces
# a CRT export the target's libc does not have.
if ! "$CC" -c "$ROOT/stdlib/runtime.c" -I "$ROOT/stdlib" -o "$TMP/runtime.o" \
        2> "$TMP/cc.log"; then
    say "FAIL: the Windows runtime does not COMPILE for mingw-w64"
    sed 's/^/      /' "$TMP/cc.log"
    exit 1
fi

printf 'int main(void){return 0;}\n' > "$TMP/main.c"

# The import libraries a real /build_windows link passes; the point of
# the gate is the CRT, so the system DLLs the runtime genuinely uses are
# supplied rather than reported as findings.
if ! "$CC" "$TMP/main.c" "$TMP/runtime.o" -o "$TMP/a.exe" \
        -lpthread -lws2_32 -lwinhttp -lbcrypt -ladvapi32 -luserenv -lshlwapi \
        2> "$TMP/ld.log"; then
    say "FAIL: the Windows runtime does not LINK against msvcrt."
    sed 's/^/      /' "$TMP/ld.log"
    say ""
    say "      An 'undefined reference to __imp_<name>' here is a CRT export"
    say "      that exists in UCRT but not in msvcrt.dll. The fix is to reach"
    say "      for the Win32 API instead (kernel32 is linkable everywhere) —"
    say "      see nurl_tz_offset in stdlib/runtime_core.c for the pattern."
    exit 1
fi

say "ok — stdlib/runtime.c compiles and links with $("$CC" -dumpmachine)"
exit 0
