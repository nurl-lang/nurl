# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""API environment configuration loading."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from app.build_routes import BuildConfig


@dataclass(frozen=True)
class ApiConfig:
    nurlc_path: str
    nurl_zig: str
    runtime_wasm_o: str
    stdlib_dir: str
    static_dir: str
    build: BuildConfig


def _default_runtime_o() -> str:
    native = "/opt/nurl/stdlib/runtime.native.o"
    return native if Path(native).is_file() else "/opt/nurl/stdlib/runtime.o"


def load_api_config() -> ApiConfig:
    nurlc_path = os.environ.get("NURLC_PATH", "/opt/nurl/build/nurlc")
    wasm_target = os.environ.get("NURL_WASM_TARGET", "wasm32-wasi")
    runtime_wasm_o = os.environ.get(
        "NURL_RUNTIME_WASM_O", "/opt/nurl/stdlib/runtime.wasm.o"
    )
    canvas_wasm_o = os.environ.get(
        "NURL_CANVAS_WASM_O", "/opt/nurl/stdlib/canvas.wasm.o"
    )
    audio_wasm_o = os.environ.get(
        "NURL_AUDIO_WASM_O", "/opt/nurl/stdlib/audio.wasm.o"
    )
    wasm_opt = os.environ.get("NURL_WASM_OPT", "wasm-opt")
    nurl_work_root = os.environ.get("NURL_WORK_ROOT", "/opt/nurl")
    stdlib_dir = os.environ.get("NURL_STDLIB_DIR", "/opt/nurl/stdlib")
    static_dir = os.environ.get(
        "NURL_API_STATIC_DIR",
        str(Path(__file__).resolve().parent.parent / "static"),
    )
    build_timeout_sec = int(os.environ.get("NURL_BUILD_TIMEOUT_SEC", "30"))
    max_source_bytes = int(
        os.environ.get("NURL_MAX_SOURCE_BYTES", str(1 * 1024 * 1024))
    )
    native_clang = os.environ.get(
        "NURL_NATIVE_CLANG",
        "/usr/bin/clang" if Path("/usr/bin/clang").exists() else "clang",
    )
    runtime_o = os.environ.get("NURL_RUNTIME_O", _default_runtime_o())
    canvas_o = os.environ.get("NURL_CANVAS_O", "/opt/nurl/stdlib/canvas.o")
    link_helper = os.environ.get("NURL_LINK_HELPER", "/opt/nurl/build/nurl-build")
    windows_target = os.environ.get("NURL_WINDOWS_TARGET", "x86_64-windows-gnu")
    runtime_win_o = os.environ.get(
        "NURL_RUNTIME_WIN_O", "/opt/nurl/stdlib/runtime.win.o"
    )
    nurl_zig = os.environ.get("NURL_ZIG", "/opt/zig/zig")
    macos_target = os.environ.get("NURL_MACOS_TARGET", "x86_64-macos-none")
    runtime_mac_o = os.environ.get(
        "NURL_RUNTIME_MAC_O", "/opt/nurl/stdlib/runtime.mac.o"
    )
    canvas_sdl2_marker = os.environ.get(
        "NURL_CANVAS_SDL2_MARKER", "/opt/nurl/stdlib/canvas.sdl2"
    )
    output_dir = os.environ.get("NURL_OUTPUT_DIR", "/app/output")
    download_ttl_sec = int(os.environ.get("NURL_DOWNLOAD_TTL_SEC", str(60 * 60)))

    return ApiConfig(
        nurlc_path=nurlc_path,
        nurl_zig=nurl_zig,
        runtime_wasm_o=runtime_wasm_o,
        stdlib_dir=stdlib_dir,
        static_dir=static_dir,
        build=BuildConfig(
            nurlc_path=nurlc_path,
            wasm_target=wasm_target,
            runtime_wasm_o=runtime_wasm_o,
            canvas_wasm_o=canvas_wasm_o,
            audio_wasm_o=audio_wasm_o,
            wasm_opt=wasm_opt,
            nurl_work_root=nurl_work_root,
            build_timeout_sec=build_timeout_sec,
            max_source_bytes=max_source_bytes,
            native_clang=native_clang,
            runtime_o=runtime_o,
            canvas_o=canvas_o,
            link_helper=link_helper,
            windows_target=windows_target,
            runtime_win_o=runtime_win_o,
            nurl_zig=nurl_zig,
            macos_target=macos_target,
            runtime_mac_o=runtime_mac_o,
            canvas_sdl2_marker=canvas_sdl2_marker,
            output_dir=output_dir,
            download_ttl_sec=download_ttl_sec,
        ),
    )
