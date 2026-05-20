# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""NURL HTTP API.

Minimal FastAPI service exposing:
  - GET  /health         liveness probe
  - POST /build          compiles NURL source to a native Linux ELF
  - POST /build_windows  cross-compiles NURL source to a Windows .exe (mingw-w64)
  - POST /build_macos    cross-compiles NURL source to a macOS Mach-O binary (zig cc)
  - POST /build_wasm     compiles NURL source to wasm32-wasi WebAssembly

Swagger UI is served automatically at /docs, ReDoc at /redoc,
and the OpenAPI schema at /openapi.json.
"""
from __future__ import annotations

import base64
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path
from typing import Literal

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

import markdown as _md

NURLC_PATH = os.environ.get("NURLC_PATH", "/opt/nurl/build/nurlc")
WASI_CLANG = os.environ.get("WASI_CLANG", "/opt/wasi-sdk/bin/clang")
RUNTIME_WASM_O = os.environ.get(
    "NURL_RUNTIME_WASM_O", "/opt/nurl/stdlib/runtime.wasm.o"
)
CANVAS_WASM_O = os.environ.get(
    "NURL_CANVAS_WASM_O", "/opt/nurl/stdlib/canvas.wasm.o"
)
AUDIO_WASM_O = os.environ.get(
    "NURL_AUDIO_WASM_O", "/opt/nurl/stdlib/audio.wasm.o"
)
WASM_OPT = os.environ.get("NURL_WASM_OPT", "wasm-opt")
# Working directory used when invoking nurlc. Import paths in NURL source
# (e.g. `$ "stdlib/core/option.nu"`) are resolved relative to this dir, so
# it must be the root that contains `stdlib/`.
NURL_WORK_ROOT = os.environ.get("NURL_WORK_ROOT", "/opt/nurl")
NURL_STDLIB_DIR = os.environ.get("NURL_STDLIB_DIR", "/opt/nurl/stdlib")
NURL_EXAMPLES_DIR = os.environ.get("NURL_EXAMPLES_DIR", "/opt/nurl/examples")
NURL_TESTS_DIR = os.environ.get("NURL_TESTS_DIR", "/opt/nurl/compiler/tests")
NURL_GRAMMAR_PATH = os.environ.get("NURL_GRAMMAR_PATH", "/opt/nurl/spec/grammar.ebnf")
NURL_README_PATH  = os.environ.get("NURL_README_PATH",  "/opt/nurl/README.md")
NURL_ROADMAP_PATH = os.environ.get("NURL_ROADMAP_PATH", "/opt/nurl/ROADMAP.md")
NURL_GOTCHAS_PATH = os.environ.get("NURL_GOTCHAS_PATH", "/opt/nurl/docs/GOTCHAS.md")
STATIC_DIR = os.environ.get("NURL_API_STATIC_DIR", str(Path(__file__).resolve().parent.parent / "static"))
BUILD_TIMEOUT_SEC = int(os.environ.get("NURL_BUILD_TIMEOUT_SEC", "30"))
MAX_SOURCE_BYTES = int(os.environ.get("NURL_MAX_SOURCE_BYTES", str(1 * 1024 * 1024)))

# Native build pipeline (mirrors nurl.sh): plain clang + stdlib/runtime.o.
# Use an absolute path by default so PATH (which contains /opt/wasi-sdk/bin
# first) doesn't accidentally route /build through the WASI SDK clang — that
# clang has a wasm32-wasi default triple and rejects the native runtime.o.
NATIVE_CLANG   = os.environ.get(
    "NURL_NATIVE_CLANG",
    "/usr/bin/clang" if Path("/usr/bin/clang").exists() else "clang",
)
# build.sh emits runtime.o as LLVM bitcode (it builds the compiler under
# `-flto`); a stock `clang` + GNU `ld` link — which is what /build does —
# rejects bitcode with "file format not recognized". build.sh also writes
# a plain-ELF `runtime.native.o` next to it for exactly this link path, so
# prefer that when present and only fall back to runtime.o otherwise.
def _default_runtime_o() -> str:
    native = "/opt/nurl/stdlib/runtime.native.o"
    return native if Path(native).is_file() else "/opt/nurl/stdlib/runtime.o"

RUNTIME_O      = os.environ.get("NURL_RUNTIME_O",  _default_runtime_o())
CANVAS_O       = os.environ.get("NURL_CANVAS_O",   "/opt/nurl/stdlib/canvas.o")

# Windows cross-compile pipeline. clang consumes the LLVM IR with an explicit
# `--target=x86_64-w64-mingw32` and mingw-w64's gcc supplies the linker, CRT,
# libgcc, and the prebuilt Windows-native `runtime.win.o` (compiled by the
# Dockerfile build stage). This path is fully separate from the Linux/wasm
# pipelines — neither is touched.
MINGW_TARGET   = os.environ.get("NURL_MINGW_TARGET", "x86_64-w64-mingw32")
MINGW_GCC      = os.environ.get("NURL_MINGW_GCC",   "/usr/bin/x86_64-w64-mingw32-gcc")
RUNTIME_WIN_O  = os.environ.get("NURL_RUNTIME_WIN_O", "/opt/nurl/stdlib/runtime.win.o")
# Static libcurl cross-build (Schannel TLS) installed by the Dockerfile under
# /opt/curl-mingw. When stdlib/runtime.win.curl is present the runtime was
# built with -DNURL_HAVE_LIBCURL and the link step must add libcurl.a plus
# the Windows system libs that schannel/winsock pull in.
MINGW_CURL_PREFIX = os.environ.get("NURL_MINGW_CURL_PREFIX", "/opt/curl-mingw")

# macOS cross-compile pipeline. zig ships darwin libc stubs for
# `x86_64-macos-none` / `aarch64-macos-none`, so `zig cc` can lower the
# IR to a Mach-O object and link it against the prebuilt `runtime.mac.o`
# (cross-compiled once at image build time) without Apple's SDK. The
# resulting binary links *only* libSystem — canvas/audio FFIs that need
# Cocoa/AudioToolbox frameworks are rejected up-front, and HTTP is
# served by the runtime's no-op stub path (no libcurl on this target).
NURL_ZIG        = os.environ.get("NURL_ZIG",         "/opt/zig/zig")
MACOS_TARGET    = os.environ.get("NURL_MACOS_TARGET","x86_64-macos-none")
RUNTIME_MAC_O   = os.environ.get("NURL_RUNTIME_MAC_O","/opt/nurl/stdlib/runtime.mac.o")
CANVAS_SDL2_MARKER = os.environ.get(
    "NURL_CANVAS_SDL2_MARKER", "/opt/nurl/stdlib/canvas.sdl2"
)
OUTPUT_DIR     = os.environ.get("NURL_OUTPUT_DIR", "/app/output")
# How long a download token stays valid. Expired artifacts are cleaned up
# lazily on the next /build or /download call.
DOWNLOAD_TTL_SEC = int(os.environ.get("NURL_DOWNLOAD_TTL_SEC", str(60 * 60)))

# Lazy import: app.mcp_server imports from app.main, so keep the import
# local to the lifespan factory below.

@asynccontextmanager
async def _lifespan(app: FastAPI):
    """Drive the MCP server's session manager for the lifetime of the app.

    FastMCP's Streamable HTTP transport uses an internal task group to
    manage per-session state; without entering ``session_manager.run()``
    requests to ``/mcp`` would fail with "Task group is not initialized".
    """
    from app.mcp_server import mcp
    async with mcp.session_manager.run():
        yield


app = FastAPI(
    title="NURL Compiler API",
    description=(
        "HTTP interface to the NURL compiler.\n\n"
        "Compiles NURL source to native x86_64 binaries (`POST /build`) "
        "or wasm32-wasi WebAssembly (`POST /build_wasm`), serves the "
        "in-browser playground at `/`, and exposes the same surface as "
        "a **Model Context Protocol** server at `POST /mcp` "
        "(Streamable HTTP transport) for LLM clients. "
        "See `GET /mcp-info` for MCP connection details — the MCP "
        "endpoint itself is an ASGI sub-app so its JSON-RPC methods "
        "aren't enumerated in this OpenAPI schema."
    ),
    version="0.1.0",
    lifespan=_lifespan,
)


class HealthResponse(BaseModel):
    status: str = Field(..., examples=["ok"])
    nurlc_available: bool = Field(
        ..., description="Whether the bundled nurlc binary is present and executable."
    )
    nurlc_path: str
    wasi_toolchain_available: bool
    stdlib_available: bool
    stdlib_dir: str
    stdlib_modules: list[str] = Field(
        default_factory=list,
        description="Relative paths of .nu files discovered under the stdlib dir.",
    )


class BuildWasmRequest(BaseModel):
    source: str = Field(
        ...,
        description="NURL source code to compile.",
        examples=["@ main → i { return 0 }\n"],
    )
    filename: str | None = Field(
        default=None,
        description="Optional logical filename used for diagnostics.",
        examples=["main.nu"],
    )
    return_format: Literal["json", "binary"] = Field(
        default="json",
        description=(
            "If 'json', the wasm bytes are returned base64-encoded in a JSON "
            "payload with compile logs. If 'binary', the raw application/wasm "
            "bytes are returned."
        ),
    )
    emit_ll: bool = Field(
        default=False,
        description="Include the intermediate LLVM IR in the JSON response.",
    )


class NurlcDiagnostic(BaseModel):
    """Structured representation of a single nurlc error line.

    Parsed from the GCC/Clang-style `file:line:col: message` format
    emitted by `die()` in the compiler. LLM agents and editor integrations
    can jump straight to the offending token without scraping stderr.
    """
    file: str
    line: int
    col: int
    message: str


# `file:line:col: message` — filename may contain drive letters or
# forward/back slashes, so the first two colons are the line/col
# separators and everything after `col: ` is the message.
_DIAG_RE = re.compile(r"^(?P<file>.+?):(?P<line>\d+):(?P<col>\d+):\s*(?P<msg>.+)$")


def parse_nurlc_diagnostics(stderr: str) -> list[NurlcDiagnostic]:
    """Extract structured diagnostics from nurlc stderr.

    Ignores lines that don't match the `file:line:col: msg` shape so
    the function tolerates auxiliary output (debug prints, warnings)
    without losing well-formed errors.
    """
    diags: list[NurlcDiagnostic] = []
    for raw in (stderr or "").splitlines():
        m = _DIAG_RE.match(raw.strip())
        if not m:
            continue
        try:
            diags.append(NurlcDiagnostic(
                file=m.group("file"),
                line=int(m.group("line")),
                col=int(m.group("col")),
                message=m.group("msg").strip(),
            ))
        except ValueError:
            continue
    return diags


class BuildWasmResponse(BaseModel):
    status: str
    message: str
    filename: str | None = None
    wasm_base64: str | None = None
    wasm_bytes: int | None = None
    nurlc_stderr: str | None = None
    nurlc_errors: list[NurlcDiagnostic] = Field(
        default_factory=list,
        description=(
            "Structured diagnostics parsed from `nurlc_stderr` "
            "(`file:line:col: message`). Empty on success."
        ),
    )
    clang_stderr: str | None = None
    llvm_ir: str | None = None
    uses_canvas: bool = Field(
        default=False,
        description=(
            "True when the program calls into the canvas_* FFI. The browser "
            "playground uses this to wire up canvas imports and enable the "
            "Asyncify runtime (so canvas_sleep can yield to the event loop)."
        ),
    )
    uses_audio: bool = Field(
        default=False,
        description=(
            "True when the program calls into the audio_* FFI. The browser "
            "playground uses this to request microphone permission and wire "
            "up the Web Audio AnalyserNode before instantiating the module."
        ),
    )


def _is_executable(path: str) -> bool:
    p = Path(path)
    return p.is_file() and os.access(p, os.X_OK)


def _nurlc_available() -> bool:
    return _is_executable(NURLC_PATH) or shutil.which("nurlc") is not None


def _wasi_toolchain_available() -> bool:
    return _is_executable(WASI_CLANG) and Path(RUNTIME_WASM_O).is_file()


# ── IR rewriting for wasm32-wasi ABI ────────────────────────────
#
# NURL emits LLVM IR with an i64-centric ABI (integers, sizes, and
# ssize-style returns are all i64; pointers are i8*). wasm32-wasi uses
# the standard wasm32 C ABI: `int`, `size_t`, `ssize_t` are all i32
# (32-bit address space, 32-bit C int). That creates a signature
# mismatch at every libc FFI boundary — wasm-ld either inserts a
# `.L<fn>_bitcast_invalid` trap stub, or emits a warning and produces
# a module that traps on the first libc call.
#
# Fix: for each known libc symbol that actually appears in the IR and
# whose NURL-native signature differs from the wasm32 one, the rewriter
#   (a) strips NURL's `declare` line,
#   (b) emits the real libc declare with wasm32 types,
#   (c) emits an internal shim `@__nurl_<name>_shim` whose signature
#       matches NURL's callsites (i64 / i8*), truncs args to the real
#       widths, forwards to the real libc, and sext/zext the return
#       back to NURL's i64,
#   (d) rewrites every `@<name>(` callsite to `@__nurl_<name>_shim(`.
#
# Entry-point rename: wasi-libc's crt1 calls `__main_argc_argv(argc,
# argv)`, not `main`. clang's C frontend renames `int main(int,char**)`
# automatically but that never happens for pre-generated LLVM IR, so
# we do it here.
#
# NB: this targets the FFI boundary only. NURL's internal arithmetic
# stays i64 — wasm has native i64 opcodes, we just need to agree with
# libc's i32 signatures at the seam.

_NURL_MAIN_DEF_RE = re.compile(
    r"(^\s*define\s+[^\n]*@)main(\s*\()", re.MULTILINE
)
_WASM_TARGET_TRIPLE = 'target triple = "wasm32-unknown-wasi"\n'

# ABI descriptors for libc symbols that differ between NURL (i64/i8*)
# and wasm32 libc (i32/i8*).
#
#   'i' — signed 32-bit C int  / ssize_t  (ret widens via sext,  arg truncs)
#   's' — unsigned 32-bit size_t          (ret widens via zext, arg truncs)
#   'p' — pointer (i8*, passes through)
#   'v' — void
#
# Entry: name → (ret_code, [param_codes]).
LIBC_WASM32_ABI: dict[str, tuple[str, list[str]]] = {
    # mem
    "malloc":  ("p", ["s"]),
    "calloc":  ("p", ["s", "s"]),
    "realloc": ("p", ["p", "s"]),
    "free":    ("v", ["p"]),  # matches already — no shim emitted
    # stdio
    "puts":    ("i", ["p"]),
    "putchar": ("i", ["i"]),
    "getchar": ("i", []),
    # string
    "strlen":  ("s", ["p"]),
    "strcmp":  ("i", ["p", "p"]),
    "strncmp": ("i", ["p", "p", "s"]),
    "strcpy":  ("p", ["p", "p"]),
    "strncpy": ("p", ["p", "p", "s"]),
    "strcat":  ("p", ["p", "p"]),
    "strdup":  ("p", ["p"]),
    # mem block
    "memcpy":  ("p", ["p", "p", "s"]),
    "memmove": ("p", ["p", "p", "s"]),
    "memset":  ("p", ["p", "i", "s"]),
    "memcmp":  ("i", ["p", "p", "s"]),
    # ctype-ish / stdlib
    "atoi":    ("i", ["p"]),
    "abs":     ("i", ["i"]),
    "exit":    ("v", ["i"]),
    "rand":    ("i", []),
    "srand":   ("v", ["s"]),
    "system":  ("i", ["p"]),
    # posix I/O (ssize_t → i for sext widening)
    "write":   ("i", ["i", "p", "s"]),
    "read":    ("i", ["i", "p", "s"]),
    "open":    ("i", ["p", "i", "i"]),
    "close":   ("i", ["i"]),
}

_REAL_TY = {"i": "i32", "s": "i32", "p": "i8*", "v": "void"}
_NURL_TY = {"i": "i64", "s": "i64", "p": "i8*", "v": "void"}


def _wasm_needs_shim(ret: str, params: list[str]) -> bool:
    return any(_REAL_TY[c] != _NURL_TY[c] for c in [ret, *params])


def _emit_wasm_shim(name: str, ret: str, params: list[str]) -> str:
    """Emit (real libc declare + NURL-typed internal shim) as IR text."""
    real_ret = _REAL_TY[ret]
    real_params = [_REAL_TY[c] for c in params]
    nurl_ret = _NURL_TY[ret]
    nurl_params = [_NURL_TY[c] for c in params]

    lines: list[str] = []
    lines.append(f"declare {real_ret} @{name}({', '.join(real_params)})")
    lines.append("")
    shim_args_decl = ", ".join(
        f"{nt} %a{i}" for i, nt in enumerate(nurl_params)
    )
    lines.append(
        f"define internal {nurl_ret} @__nurl_{name}_shim({shim_args_decl}) {{"
    )

    # Argument conversions: i64 → i32 trunc where widths differ.
    call_args: list[str] = []
    for i, (nt, rt) in enumerate(zip(nurl_params, real_params)):
        if nt == rt:
            call_args.append(f"{rt} %a{i}")
        else:
            lines.append(f"  %t{i} = trunc {nt} %a{i} to {rt}")
            call_args.append(f"{rt} %t{i}")

    call_expr = f"tail call {real_ret} @{name}({', '.join(call_args)})"
    if real_ret == "void":
        lines.append(f"  {call_expr}")
        lines.append("  ret void")
    elif real_ret == nurl_ret:
        lines.append(f"  %r = {call_expr}")
        lines.append(f"  ret {nurl_ret} %r")
    else:
        # Return-widening: size_t (unsigned) → zext; int/ssize_t → sext.
        op = "zext" if ret == "s" else "sext"
        lines.append(f"  %r = {call_expr}")
        lines.append(f"  %rw = {op} {real_ret} %r to {nurl_ret}")
        lines.append(f"  ret {nurl_ret} %rw")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def _strip_declare(text: str, name: str) -> str:
    """Remove any `declare ... @<name>(...)` line from the IR (1 occurrence)."""
    pat = re.compile(
        rf"^declare\b[^\n]*@{re.escape(name)}\s*\([^\n]*\)[^\n]*\n?",
        re.MULTILINE,
    )
    return pat.sub("", text, count=1)


# Matches an LLVM IR `c"..."` byte-string literal (with `\xx` / `\\` escapes).
# Used to mask string-constant payloads while we rewrite call-sites — NURL
# compilers like `nurlc.nu` embed LLVM IR snippets as data, and we mustn't
# touch those bytes (their `[N x i8]` type prefix would go out of sync).
_LLVM_CSTR_RE = re.compile(r'c"(?:[^"\\]|\\.)*"')


def _mask_cstrings(text: str) -> tuple[str, list[str]]:
    saved: list[str] = []

    def _sub(m: re.Match[str]) -> str:
        saved.append(m.group(0))
        return f"\x00CSTR{len(saved) - 1}\x00"

    return _LLVM_CSTR_RE.sub(_sub, text), saved


def _unmask_cstrings(text: str, saved: list[str]) -> str:
    def _sub(m: re.Match[str]) -> str:
        return saved[int(m.group(1))]

    return re.sub(r"\x00CSTR(\d+)\x00", _sub, text)


def _prepare_ir_for_wasi(ir_bytes: bytes) -> bytes:
    try:
        text = ir_bytes.decode("utf-8")
    except UnicodeDecodeError:
        return ir_bytes

    # 1) Rename user-defined `main` to wasi-libc's expected entry symbol.
    text = _NURL_MAIN_DEF_RE.sub(r"\1__main_argc_argv\2", text, count=1)

    # 2) For every libc symbol we know about, if it appears in the IR
    #    and NURL's signature conflicts with wasm32's, swap in a shim.
    #    Mask `c"..."` byte-string constants first so substitutions
    #    don't corrupt embedded IR text emitted by NURL programs that
    #    are themselves compilers (e.g. nurlc.nu) — rewriting bytes
    #    inside a constant would desync its `[N x i8]` type prefix.
    text, saved_cstrs = _mask_cstrings(text)
    shims: list[str] = []
    for name, (ret, params) in LIBC_WASM32_ABI.items():
        # Cheap substring gate — skip entries not referenced at all.
        if f"@{name}" not in text:
            continue
        if not _wasm_needs_shim(ret, params):
            continue  # signatures already match (e.g. `free(i8*)`)
        text = _strip_declare(text, name)
        # Only rewrite call-like uses (`@name(` or `@name  (`). Leave
        # function-pointer references like `@name` in bitcasts alone.
        text = re.sub(
            rf"@{re.escape(name)}(?=\s*\()",
            f"@__nurl_{name}_shim",
            text,
        )
        shims.append(_emit_wasm_shim(name, ret, params))
    text = _unmask_cstrings(text, saved_cstrs)

    if shims:
        text += "\n; ── wasm32 libc ABI shims ──\n" + "\n".join(shims)

    # 3) Prepend a target triple if the IR doesn't already declare one.
    if "target triple" not in text:
        lines = text.splitlines(keepends=True)
        i = 0
        while i < len(lines) and (lines[i].startswith(";") or lines[i].strip() == ""):
            i += 1
        lines.insert(i, _WASM_TARGET_TRIPLE)
        text = "".join(lines)

    return text.encode("utf-8")


def _list_stdlib_modules(limit: int = 200) -> list[str]:
    root = Path(NURL_STDLIB_DIR)
    if not root.is_dir():
        return []
    mods = sorted(str(p.relative_to(root)) for p in root.rglob("*.nu"))
    return mods[:limit]


def _list_examples() -> list[dict]:
    root = Path(NURL_EXAMPLES_DIR)
    if not root.is_dir():
        return []
    out: list[dict] = []
    for p in sorted(root.rglob("*.nu")):
        rel = p.relative_to(root).as_posix()
        try:
            size = p.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


def _safe_example_path(name: str) -> Path:
    root = Path(NURL_EXAMPLES_DIR).resolve()
    target = (root / name).resolve()
    if not str(target).startswith(str(root) + os.sep) and target != root:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="invalid example name")
    if not target.is_file() or target.suffix != ".nu":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="example not found")
    return target


def _list_tests() -> list[dict]:
    root = Path(NURL_TESTS_DIR)
    if not root.is_dir():
        return []
    out: list[dict] = []
    for p in sorted(root.rglob("*.nu")):
        if not p.is_file():
            continue
        rel = p.relative_to(root).as_posix()
        try:
            size = p.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


def _safe_test_path(name: str) -> Path:
    root = Path(NURL_TESTS_DIR).resolve()
    target = (root / name).resolve()
    if not str(target).startswith(str(root) + os.sep) and target != root:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="invalid test name")
    if not target.is_file() or target.suffix != ".nu":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="test not found")
    return target


@app.get("/health", response_model=HealthResponse, tags=["system"])
def health() -> HealthResponse:
    """Liveness / readiness probe."""
    return HealthResponse(
        status="ok",
        nurlc_available=_nurlc_available(),
        nurlc_path=NURLC_PATH,
        wasi_toolchain_available=_wasi_toolchain_available(),
        stdlib_available=Path(NURL_STDLIB_DIR).is_dir(),
        stdlib_dir=NURL_STDLIB_DIR,
        stdlib_modules=_list_stdlib_modules(),
    )


def _run(cmd: list[str], *, cwd: str, stdin: bytes | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            cmd,
            cwd=cwd,
            input=stdin,
            capture_output=True,
            timeout=BUILD_TIMEOUT_SEC,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail=f"{cmd[0]} timed out after {BUILD_TIMEOUT_SEC}s",
        ) from e
    except FileNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"executable not found: {cmd[0]}",
        ) from e


@app.post(
    "/build_wasm",
    tags=["build"],
    summary="Compile NURL source to wasm32-wasi WebAssembly",
    responses={
        200: {
            "description": "Compilation succeeded.",
            "content": {
                "application/json": {},
                "application/wasm": {},
            },
        },
        400: {"description": "Empty source or input validation error."},
        422: {"description": "nurlc or wasm-ld rejected the source."},
        500: {"description": "Toolchain unavailable."},
        504: {"description": "Compilation timed out."},
    },
)
def build_wasm(req: BuildWasmRequest):
    """Compile NURL source to WebAssembly.

    Pipeline:
      1. Write `source` to a temp `.nu` file.
      2. Run `nurlc <file.nu>` → LLVM IR (`.ll`) on stdout.
      3. Link the IR against the prebuilt wasm32-wasi runtime object with
         `clang --target=wasm32-wasi`, producing a `.wasm` module.
    """
    if not req.source.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="source must not be empty",
        )
    src_bytes = req.source.encode("utf-8")
    if len(src_bytes) > MAX_SOURCE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"source exceeds {MAX_SOURCE_BYTES} bytes",
        )
    if not _nurlc_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"nurlc not found at {NURLC_PATH}",
        )
    if not _wasi_toolchain_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"WASI toolchain unavailable "
                f"(clang={WASI_CLANG}, runtime={RUNTIME_WASM_O})"
            ),
        )

    basename = "main"
    if req.filename:
        stem = Path(req.filename).stem
        if stem:
            basename = "".join(c for c in stem if c.isalnum() or c in "._-") or "main"

    with tempfile.TemporaryDirectory(prefix="nurl-build-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{basename}.nu"
        ll_path = tmpdir / f"{basename}.ll"
        wasm_path = tmpdir / f"{basename}.wasm"
        nu_path.write_bytes(src_bytes)

        # 1) NURL → LLVM IR (nurlc writes IR to stdout).
        # nurlc resolves `$ "stdlib/..."` imports relative to its CWD via
        # nurl_read_file, so we run it from NURL_WORK_ROOT (which contains
        # the bundled stdlib/) and pass an absolute path to the source.
        nurlc_cwd = NURL_WORK_ROOT if Path(NURL_WORK_ROOT).is_dir() else str(tmpdir)
        nurlc_proc = _run([NURLC_PATH, str(nu_path)], cwd=nurlc_cwd)
        if nurlc_proc.returncode != 0 or not nurlc_proc.stdout:
            nurlc_stderr_txt = nurlc_proc.stderr.decode("utf-8", "replace")
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "stage": "nurlc",
                    "returncode": nurlc_proc.returncode,
                    "stderr": nurlc_stderr_txt,
                    # Parsed file:line:col: msg entries so MCP / editor
                    # clients don't have to scrape stderr themselves.
                    "errors": [d.model_dump() for d in parse_nurlc_diagnostics(nurlc_stderr_txt)],
                },
            )
        # Rename `@main` → `@__main_argc_argv` (wasi-libc's expected entry)
        # and add a wasm32-wasi target triple to silence the override warning.
        prepared_ir = _prepare_ir_for_wasi(nurlc_proc.stdout)
        ll_path.write_bytes(prepared_ir)

        # Detect whether the program calls into the canvas FFI; if so
        # we link canvas.wasm.o and later Asyncify-wrap the module.
        uses_canvas = bool(
            re.search(
                rb"@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b",
                prepared_ir,
            )
        )
        # Detect audio-FFI use. Audio imports are all synchronous polls
        # of a host-side AnalyserNode, so no Asyncify pass is required
        # for audio alone — only canvas triggers that.
        uses_audio = bool(
            re.search(
                rb"@audio_(level|bin|bin_count|peak_bin|centroid|freq_of|sample_rate|is_silent|ready)\b",
                prepared_ir,
            )
        )

        # 2) LLVM IR + runtime.wasm.o (+ canvas.wasm.o / audio.wasm.o) → .wasm
        clang_cmd = [
            WASI_CLANG,
            "--target=wasm32-wasi",
            "-O2",
            "-Wno-override-module",
            str(ll_path),
            RUNTIME_WASM_O,
        ]
        if uses_canvas:
            if not Path(CANVAS_WASM_O).is_file():
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        f"canvas FFI used but {CANVAS_WASM_O} not present. "
                        "Rebuild the container with canvas_wasm.c compiled."
                    ),
                )
            clang_cmd.append(CANVAS_WASM_O)
        if uses_audio:
            if not Path(AUDIO_WASM_O).is_file():
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        f"audio FFI used but {AUDIO_WASM_O} not present. "
                        "Rebuild the container with audio_wasm.c compiled."
                    ),
                )
            clang_cmd.append(AUDIO_WASM_O)
        if uses_canvas or uses_audio:
            # Allow undefined `canvas.*` / `audio.*` imports — they're
            # supplied by the browser host, not present in wasi-libc.
            clang_cmd += [
                "-Wl,--allow-undefined",
            ]
        # runtime.wasm.o pulls in libm symbols (sqrt/sin/cos/...).
        # wasi-libc 24.0 ships libm.a in the sysroot.
        clang_cmd += ["-lm"]
        clang_cmd += ["-o", str(wasm_path)]

        clang_proc = _run(clang_cmd, cwd=str(tmpdir))
        if clang_proc.returncode != 0 or not wasm_path.exists():
            nurlc_stderr_txt = nurlc_proc.stderr.decode("utf-8", "replace")
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "stage": "wasi-clang",
                    "returncode": clang_proc.returncode,
                    "stderr": clang_proc.stderr.decode("utf-8", "replace"),
                    "nurlc_stderr": nurlc_stderr_txt,
                    "errors": [d.model_dump() for d in parse_nurlc_diagnostics(nurlc_stderr_txt)],
                },
            )

        # 3) Asyncify-wrap when the program uses canvas — lets
        #    canvas_sleep actually suspend the wasm module and yield
        #    back to the browser event loop. We restrict the set of
        #    "async" imports to those that really need to yield, so
        #    the instrumentation overhead is minimal.
        wasm_opt_stderr = ""
        if uses_canvas:
            if shutil.which(WASM_OPT) is None:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        f"wasm-opt not found at '{WASM_OPT}'. Canvas programs "
                        "require binaryen (Debian: `apt install binaryen`)."
                    ),
                )
            asyncified = tmpdir / f"{basename}.async.wasm"
            opt_cmd = [
                WASM_OPT,
                "--asyncify",
                "--pass-arg=asyncify-imports@canvas.sleep",
                "-O2",
                str(wasm_path),
                "-o",
                str(asyncified),
            ]
            opt_proc = _run(opt_cmd, cwd=str(tmpdir))
            wasm_opt_stderr = opt_proc.stderr.decode("utf-8", "replace")
            if opt_proc.returncode != 0 or not asyncified.exists():
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail={
                        "stage": "wasm-opt asyncify",
                        "returncode": opt_proc.returncode,
                        "stderr": wasm_opt_stderr,
                    },
                )
            wasm_path = asyncified

        wasm_bytes = wasm_path.read_bytes()

    if req.return_format == "binary":
        return Response(
            content=wasm_bytes,
            media_type="application/wasm",
            headers={
                "Content-Disposition": f'attachment; filename="{basename}.wasm"',
                "X-Nurl-Uses-Canvas": "1" if uses_canvas else "0",
                "X-Nurl-Uses-Audio":  "1" if uses_audio  else "0",
            },
        )

    clang_stderr = clang_proc.stderr.decode("utf-8", "replace")
    if wasm_opt_stderr:
        clang_stderr = (clang_stderr + "\n" + wasm_opt_stderr).strip()

    nurlc_stderr_txt = nurlc_proc.stderr.decode("utf-8", "replace")
    return BuildWasmResponse(
        status="ok",
        message="compiled nurl → wasm32-wasi"
                + (" (asyncified for canvas)" if uses_canvas else "")
                + (" [+audio]" if uses_audio else ""),
        filename=req.filename,
        wasm_base64=base64.b64encode(wasm_bytes).decode("ascii"),
        wasm_bytes=len(wasm_bytes),
        nurlc_stderr=nurlc_stderr_txt or None,
        nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr_txt),
        clang_stderr=clang_stderr or None,
        llvm_ir=nurlc_proc.stdout.decode("utf-8", "replace") if req.emit_ll else None,
        uses_canvas=uses_canvas,
        uses_audio=uses_audio,
    )


# ── Native build + download registry ─────────────────────────────
#
# /build mirrors what `nurl.sh` does: nurlc → .ll → clang → native
# binary, with both artifacts written to OUTPUT_DIR. Each artifact gets
# an opaque URL-safe token; /download/{token} streams the file back.
# Tokens are kept in-process, so they're lost on restart — that's fine
# for an artifact cache.

class _DownloadEntry:
    __slots__ = ("path", "filename", "media_type", "expires_at")

    def __init__(self, path: Path, filename: str, media_type: str, expires_at: float) -> None:
        self.path = path
        self.filename = filename
        self.media_type = media_type
        self.expires_at = expires_at


_download_registry: dict[str, _DownloadEntry] = {}
_download_lock = threading.Lock()


def _gc_downloads(now: float | None = None) -> None:
    now = now if now is not None else time.time()
    with _download_lock:
        expired = [t for t, e in _download_registry.items() if e.expires_at <= now]
        for t in expired:
            entry = _download_registry.pop(t, None)
            if entry is None:
                continue
            try:
                if entry.path.is_file():
                    entry.path.unlink()
                # Clean the parent build dir if it's empty.
                parent = entry.path.parent
                if parent.is_dir() and parent.parent == Path(OUTPUT_DIR).resolve():
                    try:
                        next(parent.iterdir())
                    except StopIteration:
                        parent.rmdir()
            except OSError:
                pass


def _register_download(path: Path, media_type: str) -> str:
    token = secrets.token_urlsafe(24)
    entry = _DownloadEntry(
        path=path,
        filename=path.name,
        media_type=media_type,
        expires_at=time.time() + DOWNLOAD_TTL_SEC,
    )
    with _download_lock:
        _download_registry[token] = entry
    return token


def _download_url(request: Request | None, token: str) -> str:
    path = f"/download/{token}"
    # Prefer the explicit public URL when the deployment sets it —
    # this is the only thing that works when the request arrived
    # through the in-process ASGI transport used by the MCP server
    # (base_url="http://nurl.local"), where request.url_for() would
    # otherwise synthesise an unroutable internal URL.
    public = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")
    if public:
        return f"{public}{path}"
    if request is None:
        return path
    return str(request.url_for("download_artifact", token=token))


class BuildRequest(BaseModel):
    source: str = Field(
        ...,
        description="NURL source code to compile to a native binary.",
        examples=["@ main → i { return 0 }\n"],
    )
    filename: str | None = Field(
        default=None,
        description="Optional logical filename; the stem is used as the output basename.",
        examples=["main.nu"],
    )
    opt: str | None = Field(
        default=None,
        description="Clang optimisation flag. Defaults to -O2 (matches nurl.sh).",
        examples=["-O0", "-O2"],
    )


class BuildArtifact(BaseModel):
    name: str
    bytes: int
    download_url: str
    token: str


class BuildResponse(BaseModel):
    status: str
    message: str
    filename: str | None = None
    uses_canvas: bool = False
    nurlc_returncode: int
    nurlc_stdout_bytes: int
    nurlc_stderr: str
    clang_returncode: int | None = None
    clang_stdout: str | None = None
    clang_stderr: str | None = None
    stdout: str = Field(
        ..., description="Combined stdout from nurlc + clang (nurlc stdout is the LLVM IR; "
                         "it's omitted here to keep the payload small — use the .ll download)."
    )
    stderr: str = Field(..., description="Combined stderr from nurlc + clang.")
    nurlc_errors: list[NurlcDiagnostic] = Field(
        default_factory=list,
        description=(
            "Structured diagnostics parsed from `nurlc_stderr` "
            "(`file:line:col: message`). Empty on success."
        ),
    )
    ll_artifact: BuildArtifact | None = None
    binary_artifact: BuildArtifact | None = None


def _sanitize_basename(raw: str | None) -> str:
    if not raw:
        return "main"
    stem = Path(raw).stem
    cleaned = "".join(c for c in stem if c.isalnum() or c in "._-")
    return cleaned or "main"


@app.post(
    "/build",
    response_model=BuildResponse,
    tags=["build"],
    summary="Compile NURL source to a native binary (mirrors nurl.sh)",
    responses={
        200: {"description": "Compilation attempted; see stdout/stderr and artifacts."},
        400: {"description": "Empty source or input validation error."},
        422: {"description": "nurlc or clang rejected the source."},
        500: {"description": "Toolchain unavailable."},
        504: {"description": "Compilation timed out."},
    },
)
def build_native(req: BuildRequest, request: Request) -> BuildResponse:
    """Compile NURL source to a native ELF binary.

    Pipeline (identical to `nurl.sh`):
      1. Write `source` to a temp `.nu` file.
      2. `nurlc <file.nu>` → LLVM IR (`.ll`), saved to `/app/output/...`.
      3. `clang -O2 <ll> stdlib/runtime.o [stdlib/canvas.o [-lSDL2]] -o <bin>`.

    Both artifacts (when produced) are registered under one-shot download
    tokens and returned as URLs. `stdout`/`stderr` contain the combined
    tool output from all stages.
    """
    if not req.source.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="source must not be empty",
        )
    src_bytes = req.source.encode("utf-8")
    if len(src_bytes) > MAX_SOURCE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"source exceeds {MAX_SOURCE_BYTES} bytes",
        )
    if not _nurlc_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"nurlc not found at {NURLC_PATH}",
        )
    if shutil.which(NATIVE_CLANG) is None and not _is_executable(NATIVE_CLANG):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"native clang not found at '{NATIVE_CLANG}'",
        )
    if not Path(RUNTIME_O).is_file():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"native runtime object missing at {RUNTIME_O}",
        )
    # An LLVM-bitcode runtime.o (build.sh's -flto artifact) would only fail
    # deep in the link with a cryptic ld "file format not recognized". Catch
    # it here — it means the image lacks the plain-ELF runtime.native.o.
    if Path(RUNTIME_O).open("rb").read(4) == b"BC\xc0\xde":
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"native runtime object {RUNTIME_O} is LLVM bitcode, not an "
                "ELF object — GNU ld cannot link it. Rebuild the image so "
                "build.sh produces stdlib/runtime.native.o."
            ),
        )

    _gc_downloads()

    basename = _sanitize_basename(req.filename)
    opt_flag = req.opt if req.opt and req.opt.startswith("-O") else "-O2"

    # Per-build subdir so concurrent requests don't stomp on each other
    # and GC can drop everything in one go.
    output_root = Path(OUTPUT_DIR)
    output_root.mkdir(parents=True, exist_ok=True)
    build_dir = output_root / f"build-{uuid.uuid4().hex[:12]}"
    build_dir.mkdir(parents=True, exist_ok=False)

    ll_path = build_dir / f"{basename}.ll"
    bin_path = build_dir / basename

    stdout_log: list[str] = []
    stderr_log: list[str] = []

    with tempfile.TemporaryDirectory(prefix="nurl-build-native-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{basename}.nu"
        nu_path.write_bytes(src_bytes)

        # 1) nurlc → LLVM IR (stdout).
        nurlc_cwd = NURL_WORK_ROOT if Path(NURL_WORK_ROOT).is_dir() else str(tmpdir)
        nurlc_proc = _run([NURLC_PATH, str(nu_path)], cwd=nurlc_cwd)
        nurlc_stderr = nurlc_proc.stderr.decode("utf-8", "replace")
        stderr_log.append(f"[nurlc] {nurlc_stderr}" if nurlc_stderr else "")

        if nurlc_proc.returncode != 0 or not nurlc_proc.stdout:
            # Surface as a structured response (status=error) rather than
            # 422 — the caller asked for stdout/stderr and we have it.
            return BuildResponse(
                status="error",
                message="nurlc failed",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout or b""),
                nurlc_stderr=nurlc_stderr,
                stdout="",
                stderr="\n".join(s for s in stderr_log if s).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        ll_path.write_bytes(nurlc_proc.stdout)

        # nurlc emits headers + declares even for unparseable sources and still
        # exits 0, so an IR with no `define ... @main` is the most common way
        # /build fails with a cryptic `undefined reference to main` from ld.
        # Surface that up-front with a friendlier diagnostic.
        if not re.search(rb"^\s*define\s+i32\s+@main\s*\(", nurlc_proc.stdout, re.MULTILINE):
            hint = (
                "nurlc produced IR without an `@main` definition. "
                "NURL's entry point is `@ main → i { ... }` — not "
                "`fn main() -> i { ... }`. See /examples for working sources."
            )
            return BuildResponse(
                status="error",
                message="no @main in generated IR",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout),
                nurlc_stderr=nurlc_stderr,
                clang_returncode=None,
                clang_stdout=None,
                clang_stderr=None,
                stdout="",
                stderr=("\n".join(s for s in stderr_log if s) + "\n[nurl] " + hint).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        uses_canvas = bool(
            re.search(
                rb"@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b",
                nurlc_proc.stdout,
            )
        )

        # 2) clang link (mirrors nurl.sh).
        # -Wno-override-module silences the cosmetic
        #   "overriding the module target triple with x86_64-pc-linux-gnu"
        # warning that clang emits because nurlc's IR has no explicit triple.
        clang_cmd: list[str] = [
            NATIVE_CLANG, opt_flag, "-Wno-override-module",
            str(ll_path), RUNTIME_O,
        ]
        # runtime.native.o is a single object file, so the linker pulls in
        # *every* symbol it references — including the optional FFI libraries
        # build.sh detected at image-build time, even for user programs that
        # never touch them. build.sh drops a stdlib/runtime.<name> marker for
        # each one it compiled in; mirror nurl.sh and add the matching libs.
        # -lm (libm: sqrt/sin/cos/...) and -lpthread are always needed.
        extra_libs: list[str] = ["-lm", "-lpthread"]
        runtime_dir = os.path.dirname(RUNTIME_O)
        for marker, libs in (
            ("runtime.curl",    ["-lcurl"]),
            ("runtime.openssl", ["-lssl", "-lcrypto"]),
            ("runtime.sqlite3", ["-lsqlite3"]),
            ("runtime.pq",      ["-lpq"]),
            ("runtime.z",       ["-lz"]),
            ("runtime.zstd",    ["-lzstd"]),
        ):
            if Path(os.path.join(runtime_dir, marker)).is_file():
                extra_libs += libs
        if uses_canvas:
            if not Path(CANVAS_O).is_file():
                # Clean up the .ll we wrote so we don't leak a dangling artifact.
                try:
                    ll_path.unlink()
                    build_dir.rmdir()
                except OSError:
                    pass
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        f"canvas FFI used but {CANVAS_O} not present. "
                        "Rebuild the container with canvas.c compiled."
                    ),
                )
            clang_cmd.append(CANVAS_O)
            if Path(CANVAS_SDL2_MARKER).is_file():
                extra_libs.append("-lSDL2")
        clang_cmd += ["-o", str(bin_path), *extra_libs]

        clang_proc = _run(clang_cmd, cwd=str(tmpdir))
        clang_stdout = clang_proc.stdout.decode("utf-8", "replace")
        clang_stderr = clang_proc.stderr.decode("utf-8", "replace")
        if clang_stdout:
            stdout_log.append(f"[clang] {clang_stdout}")
        if clang_stderr:
            stderr_log.append(f"[clang] {clang_stderr}")

    # Register whatever artifacts actually landed on disk.
    ll_artifact: BuildArtifact | None = None
    if ll_path.is_file():
        token = _register_download(ll_path, "text/plain")
        ll_artifact = BuildArtifact(
            name=ll_path.name,
            bytes=ll_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    binary_artifact: BuildArtifact | None = None
    if bin_path.is_file():
        try:
            bin_path.chmod(0o755)
        except OSError:
            pass
        token = _register_download(bin_path, "application/octet-stream")
        binary_artifact = BuildArtifact(
            name=bin_path.name,
            bytes=bin_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    ok = clang_proc.returncode == 0 and binary_artifact is not None
    return BuildResponse(
        status="ok" if ok else "error",
        message=(
            "compiled nurl → native binary"
            if ok
            else "build failed (see stderr)"
        ),
        filename=req.filename,
        uses_canvas=uses_canvas,
        nurlc_returncode=nurlc_proc.returncode,
        nurlc_stdout_bytes=len(nurlc_proc.stdout),
        nurlc_stderr=nurlc_stderr,
        clang_returncode=clang_proc.returncode,
        clang_stdout=clang_stdout or None,
        clang_stderr=clang_stderr or None,
        stdout="\n".join(s for s in stdout_log if s).strip(),
        stderr="\n".join(s for s in stderr_log if s).strip(),
        nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
        ll_artifact=ll_artifact,
        binary_artifact=binary_artifact,
    )


# ── Windows cross-compile (POST /build_windows) ──────────────────
#
# Mirrors /build but routes through clang's mingw-w64 target to produce a
# PE/COFF .exe. The pipeline is intentionally a copy rather than a flag on
# /build — keeps the Linux ELF path untouched and lets the Windows path
# evolve (extra link flags, sysroot tweaks, future SDL2-mingw support)
# without risking regressions on the well-trodden Linux build.
#
# canvas/audio FFI is rejected up-front: the Windows-side SDL2 and
# microphone bridges aren't compiled into the container.

@app.post(
    "/build_windows",
    response_model=BuildResponse,
    tags=["build"],
    summary="Cross-compile NURL source to a Windows .exe (mingw-w64)",
    responses={
        200: {"description": "Compilation attempted; see stdout/stderr and artifacts."},
        400: {"description": "Empty source, oversized source, or unsupported FFI."},
        500: {"description": "mingw-w64 toolchain unavailable."},
        504: {"description": "Compilation timed out."},
    },
)
def build_windows(req: BuildRequest, request: Request) -> BuildResponse:
    """Compile NURL source to a Windows x86_64 .exe via mingw-w64.

    Pipeline:
      1. Write `source` to a temp `.nu` file.
      2. `nurlc <file.nu>` → LLVM IR (`.ll`).
      3. `clang --target=x86_64-w64-mingw32 -O2 <ll> runtime.win.o -o <exe>`.

    The runtime is a precompiled `runtime.win.o` produced once at image
    build time with `x86_64-w64-mingw32-gcc`. clang's mingw driver finds
    the matching CRT/libgcc/binutils linker via the standard sysroot
    layout that `gcc-mingw-w64-x86-64` installs under `/usr/x86_64-w64-mingw32/`.
    """
    if not req.source.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="source must not be empty",
        )
    src_bytes = req.source.encode("utf-8")
    if len(src_bytes) > MAX_SOURCE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"source exceeds {MAX_SOURCE_BYTES} bytes",
        )
    if not _nurlc_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"nurlc not found at {NURLC_PATH}",
        )
    # We use clang as the IR consumer + driver, but mingw's gcc must be
    # present so its sysroot (CRT, libgcc, ld) is discoverable by clang.
    if shutil.which(NATIVE_CLANG) is None and not _is_executable(NATIVE_CLANG):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"clang not found at '{NATIVE_CLANG}'",
        )
    if shutil.which(MINGW_GCC) is None and not _is_executable(MINGW_GCC):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"mingw-w64 toolchain not found at '{MINGW_GCC}'. "
                "Install gcc-mingw-w64-x86-64 and rebuild the container."
            ),
        )
    if not Path(RUNTIME_WIN_O).is_file():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"Windows runtime object missing at {RUNTIME_WIN_O}. "
                "Rebuild the container so the build stage produces runtime.win.o."
            ),
        )

    _gc_downloads()

    basename = _sanitize_basename(req.filename)
    opt_flag = req.opt if req.opt and req.opt.startswith("-O") else "-O2"

    output_root = Path(OUTPUT_DIR)
    output_root.mkdir(parents=True, exist_ok=True)
    build_dir = output_root / f"buildwin-{uuid.uuid4().hex[:12]}"
    build_dir.mkdir(parents=True, exist_ok=False)

    ll_path = build_dir / f"{basename}.ll"
    exe_path = build_dir / f"{basename}.exe"

    stdout_log: list[str] = []
    stderr_log: list[str] = []

    with tempfile.TemporaryDirectory(prefix="nurl-build-windows-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{basename}.nu"
        nu_path.write_bytes(src_bytes)

        nurlc_cwd = NURL_WORK_ROOT if Path(NURL_WORK_ROOT).is_dir() else str(tmpdir)
        nurlc_proc = _run([NURLC_PATH, str(nu_path)], cwd=nurlc_cwd)
        nurlc_stderr = nurlc_proc.stderr.decode("utf-8", "replace")
        stderr_log.append(f"[nurlc] {nurlc_stderr}" if nurlc_stderr else "")

        if nurlc_proc.returncode != 0 or not nurlc_proc.stdout:
            return BuildResponse(
                status="error",
                message="nurlc failed",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout or b""),
                nurlc_stderr=nurlc_stderr,
                stdout="",
                stderr="\n".join(s for s in stderr_log if s).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        ll_path.write_bytes(nurlc_proc.stdout)

        if not re.search(rb"^\s*define\s+i32\s+@main\s*\(", nurlc_proc.stdout, re.MULTILINE):
            hint = (
                "nurlc produced IR without an `@main` definition. "
                "NURL's entry point is `@ main → i { ... }`."
            )
            return BuildResponse(
                status="error",
                message="no @main in generated IR",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout),
                nurlc_stderr=nurlc_stderr,
                clang_returncode=None,
                clang_stdout=None,
                clang_stderr=None,
                stdout="",
                stderr=("\n".join(s for s in stderr_log if s) + "\n[nurl] " + hint).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        uses_canvas = bool(
            re.search(
                rb"@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b",
                nurlc_proc.stdout,
            )
        )
        uses_audio = bool(re.search(rb"@audio_[a-z_]+\b", nurlc_proc.stdout))

        # Reject FFIs that have no Windows back-end in this container.
        if uses_canvas or uses_audio:
            try:
                ll_path.unlink()
                build_dir.rmdir()
            except OSError:
                pass
            unsupported = []
            if uses_canvas: unsupported.append("canvas")
            if uses_audio:  unsupported.append("audio")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Windows build does not support FFI: {', '.join(unsupported)}. "
                    "Use Build WASM for canvas/audio programs."
                ),
            )

        # Two-step: clang lowers IR → COFF object with the mingw triple,
        # then mingw-gcc drives the link. We can't let clang link directly
        # because Debian's mingw packages install libgcc.a/libgcc_eh.a under
        # `/usr/lib/gcc/x86_64-w64-mingw32/<ver>-{posix,win32}/` rather than
        # the upstream-mingw layout clang's driver searches; mingw-gcc knows
        # its own `-print-libgcc-file-name` path and links cleanly.
        obj_path = build_dir / f"{basename}.o"
        clang_cmd: list[str] = [
            NATIVE_CLANG, opt_flag, "-Wno-override-module",
            f"--target={MINGW_TARGET}",
            "-c", str(ll_path),
            "-o", str(obj_path),
        ]
        clang_proc = _run(clang_cmd, cwd=str(tmpdir))
        clang_stdout = clang_proc.stdout.decode("utf-8", "replace")
        clang_stderr = clang_proc.stderr.decode("utf-8", "replace")
        if clang_stdout:
            stdout_log.append(f"[clang] {clang_stdout}")
        if clang_stderr:
            stderr_log.append(f"[clang] {clang_stderr}")

        link_proc = None
        if clang_proc.returncode == 0 and obj_path.is_file():
            link_cmd: list[str] = [
                MINGW_GCC, opt_flag,
                str(obj_path), RUNTIME_WIN_O,
                "-o", str(exe_path),
            ]
            # When the Windows runtime was built with -DNURL_HAVE_LIBCURL
            # (Dockerfile drops a stdlib/runtime.win.curl marker), link the
            # static libcurl bundle plus the Windows system libs schannel /
            # winsock require. Static + schannel keeps the .exe self-contained.
            if Path(os.path.join(os.path.dirname(RUNTIME_WIN_O), "runtime.win.curl")).is_file():
                link_cmd.extend([
                    f"-L{MINGW_CURL_PREFIX}/lib",
                    "-lcurl",
                    "-lws2_32", "-lcrypt32", "-lbcrypt", "-lncrypt",
                    "-lsecur32", "-ladvapi32",
                ])
            link_proc = _run(link_cmd, cwd=str(tmpdir))
            link_stdout = link_proc.stdout.decode("utf-8", "replace")
            link_stderr = link_proc.stderr.decode("utf-8", "replace")
            if link_stdout:
                stdout_log.append(f"[mingw-gcc] {link_stdout}")
            if link_stderr:
                stderr_log.append(f"[mingw-gcc] {link_stderr}")
            # Clean intermediate object — only .ll and .exe are downloadable.
            try:
                obj_path.unlink()
            except OSError:
                pass

    ll_artifact: BuildArtifact | None = None
    if ll_path.is_file():
        token = _register_download(ll_path, "text/plain")
        ll_artifact = BuildArtifact(
            name=ll_path.name,
            bytes=ll_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    exe_artifact: BuildArtifact | None = None
    if exe_path.is_file():
        token = _register_download(exe_path, "application/vnd.microsoft.portable-executable")
        exe_artifact = BuildArtifact(
            name=exe_path.name,
            bytes=exe_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    link_rc = link_proc.returncode if link_proc is not None else None
    ok = (
        clang_proc.returncode == 0
        and link_rc == 0
        and exe_artifact is not None
    )
    # Surface the failing stage's exit code via clang_returncode so the
    # playground's existing rendering ("clang exit N") still tells the truth.
    reported_rc = clang_proc.returncode if clang_proc.returncode != 0 else (link_rc if link_rc is not None else clang_proc.returncode)
    return BuildResponse(
        status="ok" if ok else "error",
        message=(
            "compiled nurl → Windows .exe (mingw-w64)"
            if ok
            else "windows build failed (see stderr)"
        ),
        filename=req.filename,
        uses_canvas=False,
        nurlc_returncode=nurlc_proc.returncode,
        nurlc_stdout_bytes=len(nurlc_proc.stdout),
        nurlc_stderr=nurlc_stderr,
        clang_returncode=reported_rc,
        clang_stdout=clang_stdout or None,
        clang_stderr=clang_stderr or None,
        stdout="\n".join(s for s in stdout_log if s).strip(),
        stderr="\n".join(s for s in stderr_log if s).strip(),
        nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
        ll_artifact=ll_artifact,
        binary_artifact=exe_artifact,
    )


# ── macOS cross-compile (POST /build_macos) ──────────────────────
#
# Mirrors /build_windows but uses `zig cc` to target Mach-O. Zig bundles
# darwin libc stubs (`.tbd` files for libSystem) so the link succeeds
# without Apple's SDK — and crucially without redistributing any of
# Apple's files. The resulting binary links *only* libSystem, which is
# the playground's stated contract for macOS support:
# "simple standalone binary, nothing bundled".
#
# canvas/audio FFI is rejected up-front (those need Cocoa/AudioToolbox
# framework linkage, which the zig-cc-only path cannot provide). HTTP
# uses the runtime's stub fallback — it links but every call reports
# HttpErr::Other. This intentionally mirrors the "no oheistiedostoja"
# rule documented for macOS.

@app.post(
    "/build_macos",
    response_model=BuildResponse,
    tags=["build"],
    summary="Cross-compile NURL source to a macOS Mach-O binary (zig cc)",
    responses={
        200: {"description": "Compilation attempted; see stdout/stderr and artifacts."},
        400: {"description": "Empty source, oversized source, or unsupported FFI."},
        500: {"description": "zig toolchain unavailable."},
        504: {"description": "Compilation timed out."},
    },
)
def build_macos(req: BuildRequest, request: Request) -> BuildResponse:
    """Compile NURL source to a macOS Mach-O binary via `zig cc`.

    Pipeline:
      1. Write `source` to a temp `.nu` file.
      2. `nurlc <file.nu>` → LLVM IR (`.ll`).
      3. `zig cc --target=<MACOS_TARGET> -O2 <ll> runtime.mac.o -o <bin>`.

    The binary is unsigned — users will need to clear the quarantine
    attribute (`xattr -d com.apple.quarantine <bin>`) or allow it via
    Gatekeeper. Only libSystem is linked: canvas/audio FFIs are rejected.
    """
    if not req.source.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="source must not be empty",
        )
    src_bytes = req.source.encode("utf-8")
    if len(src_bytes) > MAX_SOURCE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"source exceeds {MAX_SOURCE_BYTES} bytes",
        )
    if not _nurlc_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"nurlc not found at {NURLC_PATH}",
        )
    if shutil.which(NURL_ZIG) is None and not _is_executable(NURL_ZIG):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"zig toolchain not found at '{NURL_ZIG}'. "
                "Rebuild the container so the build stage installs zig."
            ),
        )
    if not Path(RUNTIME_MAC_O).is_file():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"macOS runtime object missing at {RUNTIME_MAC_O}. "
                "Rebuild the container so the build stage produces runtime.mac.o."
            ),
        )

    _gc_downloads()

    basename = _sanitize_basename(req.filename)
    opt_flag = req.opt if req.opt and req.opt.startswith("-O") else "-O2"

    output_root = Path(OUTPUT_DIR)
    output_root.mkdir(parents=True, exist_ok=True)
    build_dir = output_root / f"buildmac-{uuid.uuid4().hex[:12]}"
    build_dir.mkdir(parents=True, exist_ok=False)

    ll_path = build_dir / f"{basename}.ll"
    bin_path = build_dir / basename

    stdout_log: list[str] = []
    stderr_log: list[str] = []

    with tempfile.TemporaryDirectory(prefix="nurl-build-macos-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{basename}.nu"
        nu_path.write_bytes(src_bytes)

        nurlc_cwd = NURL_WORK_ROOT if Path(NURL_WORK_ROOT).is_dir() else str(tmpdir)
        nurlc_proc = _run([NURLC_PATH, str(nu_path)], cwd=nurlc_cwd)
        nurlc_stderr = nurlc_proc.stderr.decode("utf-8", "replace")
        stderr_log.append(f"[nurlc] {nurlc_stderr}" if nurlc_stderr else "")

        if nurlc_proc.returncode != 0 or not nurlc_proc.stdout:
            return BuildResponse(
                status="error",
                message="nurlc failed",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout or b""),
                nurlc_stderr=nurlc_stderr,
                stdout="",
                stderr="\n".join(s for s in stderr_log if s).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        ll_path.write_bytes(nurlc_proc.stdout)

        if not re.search(rb"^\s*define\s+i32\s+@main\s*\(", nurlc_proc.stdout, re.MULTILINE):
            hint = (
                "nurlc produced IR without an `@main` definition. "
                "NURL's entry point is `@ main → i { ... }`."
            )
            return BuildResponse(
                status="error",
                message="no @main in generated IR",
                filename=req.filename,
                uses_canvas=False,
                nurlc_returncode=nurlc_proc.returncode,
                nurlc_stdout_bytes=len(nurlc_proc.stdout),
                nurlc_stderr=nurlc_stderr,
                clang_returncode=None,
                clang_stdout=None,
                clang_stderr=None,
                stdout="",
                stderr=("\n".join(s for s in stderr_log if s) + "\n[nurl] " + hint).strip(),
                nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
                ll_artifact=None,
                binary_artifact=None,
            )

        uses_canvas = bool(
            re.search(
                rb"@canvas_(open|present|sleep|should_close|close|mouse_x|mouse_y|mouse_btn)\b",
                nurlc_proc.stdout,
            )
        )
        uses_audio = bool(re.search(rb"@audio_[a-z_]+\b", nurlc_proc.stdout))

        # Reject FFIs that have no macOS back-end in this container.
        if uses_canvas or uses_audio:
            try:
                ll_path.unlink()
                build_dir.rmdir()
            except OSError:
                pass
            unsupported = []
            if uses_canvas: unsupported.append("canvas")
            if uses_audio:  unsupported.append("audio")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"macOS build does not support FFI: {', '.join(unsupported)}. "
                    "Use Build WASM for canvas/audio programs."
                ),
            )

        # Single-step: zig cc consumes the IR directly, picks its
        # bundled darwin libc stubs for the target triple, and drives
        # its internal lld to produce a Mach-O binary. No separate
        # link stage (unlike mingw, where Debian's sysroot layout
        # requires handing the link off to mingw-gcc).
        #
        # Zig sets HOME / cache dirs under $XDG_CACHE_HOME or $HOME.
        # The non-root container user's HOME is /app, which is writable
        # by that user, so zig can write its (tiny) global cache there.
        zig_cmd: list[str] = [
            NURL_ZIG, "cc",
            f"--target={MACOS_TARGET}",
            opt_flag, "-Wno-override-module",
            str(ll_path), RUNTIME_MAC_O,
            "-o", str(bin_path),
        ]
        # runtime.c links libm calls on POSIX; on macOS those live in
        # libSystem (which zig links implicitly), so no -lm needed.
        clang_proc = _run(zig_cmd, cwd=str(tmpdir))
        clang_stdout = clang_proc.stdout.decode("utf-8", "replace")
        clang_stderr = clang_proc.stderr.decode("utf-8", "replace")
        if clang_stdout:
            stdout_log.append(f"[zig cc] {clang_stdout}")
        if clang_stderr:
            stderr_log.append(f"[zig cc] {clang_stderr}")

    ll_artifact: BuildArtifact | None = None
    if ll_path.is_file():
        token = _register_download(ll_path, "text/plain")
        ll_artifact = BuildArtifact(
            name=ll_path.name,
            bytes=ll_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    bin_artifact: BuildArtifact | None = None
    if bin_path.is_file():
        try:
            bin_path.chmod(0o755)
        except OSError:
            pass
        token = _register_download(bin_path, "application/x-mach-binary")
        bin_artifact = BuildArtifact(
            name=bin_path.name,
            bytes=bin_path.stat().st_size,
            download_url=_download_url(request, token),
            token=token,
        )

    ok = clang_proc.returncode == 0 and bin_artifact is not None
    return BuildResponse(
        status="ok" if ok else "error",
        message=(
            f"compiled nurl → macOS Mach-O ({MACOS_TARGET})"
            if ok
            else "macos build failed (see stderr)"
        ),
        filename=req.filename,
        uses_canvas=False,
        nurlc_returncode=nurlc_proc.returncode,
        nurlc_stdout_bytes=len(nurlc_proc.stdout),
        nurlc_stderr=nurlc_stderr,
        clang_returncode=clang_proc.returncode,
        clang_stdout=clang_stdout or None,
        clang_stderr=clang_stderr or None,
        stdout="\n".join(s for s in stdout_log if s).strip(),
        stderr="\n".join(s for s in stderr_log if s).strip(),
        nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
        ll_artifact=ll_artifact,
        binary_artifact=bin_artifact,
    )


@app.get(
    "/download/{token}",
    tags=["build"],
    summary="Download a build artifact (.ll or native binary) produced by /build",
    responses={
        200: {"description": "Artifact stream."},
        404: {"description": "Unknown or expired token."},
    },
)
def download_artifact(token: str) -> FileResponse:
    _gc_downloads()
    with _download_lock:
        entry = _download_registry.get(token)
    if entry is None or not entry.path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="unknown or expired token")
    return FileResponse(
        path=str(entry.path),
        media_type=entry.media_type,
        filename=entry.filename,
    )


class ExampleInfo(BaseModel):
    name: str
    path: str
    bytes: int


class ExampleContent(BaseModel):
    name: str
    source: str
    bytes: int


@app.get("/examples", response_model=list[ExampleInfo], tags=["examples"])
def list_examples() -> list[ExampleInfo]:
    """List bundled NURL example programs."""
    return [ExampleInfo(**e) for e in _list_examples()]


@app.get("/examples/{name:path}", response_model=ExampleContent, tags=["examples"])
def get_example(name: str) -> ExampleContent:
    """Return the source of a bundled example."""
    target = _safe_example_path(name)
    source = target.read_text(encoding="utf-8", errors="replace")
    return ExampleContent(name=name, source=source, bytes=len(source.encode("utf-8")))


class TestInfo(BaseModel):
    name: str
    path: str
    bytes: int


class TestContent(BaseModel):
    name: str
    source: str
    bytes: int


@app.get("/tests", response_model=list[TestInfo], tags=["tests"])
def list_tests() -> list[TestInfo]:
    """List bundled NURL compiler test programs."""
    return [TestInfo(**t) for t in _list_tests()]


@app.get("/tests/{name:path}", response_model=TestContent, tags=["tests"])
def get_test(name: str) -> TestContent:
    """Return the source of a bundled compiler test."""
    target = _safe_test_path(name)
    source = target.read_text(encoding="utf-8", errors="replace")
    return TestContent(name=name, source=source, bytes=len(source.encode("utf-8")))


# ── Stdlib browsing ─────────────────────────────────────────────
#
# A thin viewer page that loads Monaco from CDN, fetches the stdlib file
# tree from `/stdlib`, and renders a single file at a time using the same
# NURL Monarch grammar + `nurl-dark` theme as the playground. Read-only.

_STDLIB_VIEWER_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<title>NURL Stdlib · Browser</title>
<style>
  :root {
    --bg: #0f1115;
    --panel: #161a21;
    --panel-2: #1d222b;
    --border: #262c38;
    --fg: #e6e8ee;
    --fg-dim: #9aa3b2;
    --accent: #7cc4ff;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    display: flex; flex-direction: column;
  }
  header {
    display: flex; align-items: center; gap: 1rem;
    padding: .55rem 1rem; border-bottom: 1px solid var(--border);
    background: var(--panel);
  }
  header h1 { margin: 0; font-size: 1rem; font-weight: 600; }
  header .spacer { flex: 1; }
  header a { color: var(--fg-dim); text-decoration: none; font-size: .85rem; margin-left: .75rem; }
  header a:hover { color: var(--fg); }
  header .crumb { font-size: .85rem; color: var(--fg-dim); }
  header .crumb b { color: var(--fg); font-weight: 600; }
  main {
    flex: 1; display: grid;
    grid-template-columns: 260px 1fr;
    gap: 1px; background: var(--border);
    min-height: 0;
  }
  aside {
    background: var(--panel); overflow: auto;
    padding: .5rem 0; min-width: 0;
  }
  aside .group {
    font-size: .7rem; text-transform: uppercase; letter-spacing: .08em;
    color: var(--fg-dim); padding: .65rem .85rem .25rem;
  }
  aside ul { list-style: none; margin: 0; padding: 0; }
  aside li a {
    display: block; padding: .25rem .85rem .25rem 1.4rem;
    color: var(--fg); text-decoration: none;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    font-size: .82rem; line-height: 1.4;
    border-left: 2px solid transparent;
  }
  aside li a:hover { background: var(--panel-2); }
  aside li a.active {
    background: var(--panel-2);
    border-left-color: var(--accent);
    color: var(--accent);
  }
  aside li a .size {
    color: var(--fg-dim); float: right; font-size: .72rem;
  }
  section.viewer {
    background: var(--panel); display: flex; flex-direction: column;
    min-height: 0; min-width: 0;
  }
  .viewer-header {
    font-size: .75rem;
    color: var(--fg-dim);
    padding: .4rem .85rem; border-bottom: 1px solid var(--border);
    display: flex; align-items: center; gap: .75rem;
  }
  .viewer-header .path {
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    color: var(--fg); font-size: .82rem;
  }
  .viewer-header .spacer { flex: 1; }
  .viewer-header a, .viewer-header button {
    color: var(--fg-dim); text-decoration: none; font-size: .78rem;
    background: transparent; border: 1px solid var(--border);
    border-radius: 6px; padding: .25rem .55rem; cursor: pointer;
    font-family: inherit;
  }
  .viewer-header a:hover, .viewer-header button:hover {
    color: var(--fg); border-color: var(--fg-dim);
  }
  #editor { flex: 1; width: 100%; min-height: 0; display: none; }
  #editor.ready { display: block; }
  .empty {
    flex: 1; display: flex; align-items: center; justify-content: center;
    color: var(--fg-dim); font-size: .9rem;
  }
</style>
</head>
<body>
<header>
  <h1>NURL Stdlib</h1>
  <span class="crumb" id="crumb">— pick a module —</span>
  <div class="spacer"></div>
  <a href="/" target="_self">← Playground</a>
  <a href="/readme" target="_blank" rel="noopener">README</a>
  <a href="/grammar" target="_blank" rel="noopener">Grammar</a>
</header>

<main>
  <aside id="tree"></aside>
  <section class="viewer">
    <div class="viewer-header">
      <span class="path" id="currentPath">(no file)</span>
      <span class="spacer"></span>
      <a id="rawLink" href="#" target="_blank" rel="noopener" hidden>raw</a>
      <button id="copyBtn" type="button" hidden>copy</button>
    </div>
    <div id="editor"></div>
    <div id="emptyMsg" class="empty">Select a stdlib module on the left to view it.</div>
  </section>
</main>

<script src="https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs/loader.js"></script>
<script>
  window.__monacoReady = new Promise((resolve) => {
    require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } });
    require(['vs/editor/editor.main'], () => resolve(window.monaco));
  });
</script>

<script type="module">
// Same Monarch grammar + theme used by the playground (api/static/index.html).
// Kept inline so the viewer page is self-contained.
const NURL_MONARCH = {
  defaultToken: "",
  tokenPostfix: ".nurl",
  tokenizer: {
    root: [
      [/\\/\\/.*$/, "comment"],
      [/`/, { token: "string.quote", bracket: "@open", next: "@string" }],
      [/\\$(?=\\s*`)/, "keyword.control.import"],
      [/&(?=\\s*`)/,  "keyword.control.ffi"],
      [/(@)(\\s+)([a-z_][\\w]*)/, ["keyword.other.func", "white", "entity.name.function"]],
      [/(%)(\\s+)([A-Za-z_][\\w]*)/, ["keyword.other.trait", "white", "type.identifier"]],
      [/(:)(\\s*)(\\|)(\\s*)([A-Za-z_][\\w]*)/,
        ["keyword", "white", "keyword", "white", "type.identifier"]],
      [/(:)(\\s+)([A-Z][\\w]*)(\\s*)(\\{)/,
        ["keyword", "white", "type.identifier", "white", "@brackets"]],
      [/\\d+\\.\\d+([eE][+\\-]?\\d+)?/, "number.float"],
      [/\\d+/,                       "number"],
      [/\\b(T|F)\\b/, "constant.language.boolean"],
      [/\\b(i|u|f|b|s|v)\\b/, "type"],
      [/\\b[A-Z][\\w]*\\b/, "type.identifier"],
      [/→/,              "keyword.operator"],
      [/\\^/,             "keyword.control.return"],
      [/\\?\\?/,           "keyword.control"],
      [/\\?/,             "keyword.control"],
      [/~/,              "keyword.control"],
      [/;/,              "keyword"],
      [/\\\\/,             "keyword"],
      [/\\bZ\\b/,          "keyword"],
      [/(==|!=|<=|>=)/,  "keyword.operator"],
      [/[<>]/,           "keyword.operator"],
      [/[+\\-*/%]/,       "keyword.operator.arithmetic"],
      [/[&|!]/,          "keyword.operator.logical"],
      [/[=:]/,           "keyword.operator.assign"],
      [/[.#@$]/,         "keyword.operator"],
      [/[{}()\\[\\]]/, "@brackets"],
      [/,/,          "delimiter"],
      [/[a-zA-Z_]\\w*/, "identifier"],
      [/\\s+/, "white"],
    ],
    string: [
      [/\\\\[ntr\\\\`]/,                                    "string.escape"],
      [/[^\\\\`]+/,                                       "string"],
      [/`/, { token: "string.quote", bracket: "@close", next: "@pop" }],
    ],
  },
};

const NURL_THEME_RULES = [
  { token: "comment",                     foreground: "6A9955", fontStyle: "italic" },
  { token: "string",                      foreground: "CE9178" },
  { token: "string.quote",                foreground: "CE9178" },
  { token: "string.escape",               foreground: "D7BA7D" },
  { token: "number",                      foreground: "B5CEA8" },
  { token: "number.float",                foreground: "B5CEA8" },
  { token: "constant.language.boolean",   foreground: "569CD6" },
  { token: "type",                        foreground: "4EC9B0" },
  { token: "type.identifier",             foreground: "4EC9B0" },
  { token: "entity.name.function",        foreground: "DCDCAA" },
  { token: "keyword",                     foreground: "C586C0" },
  { token: "keyword.control",             foreground: "C586C0" },
  { token: "keyword.control.import",      foreground: "C586C0" },
  { token: "keyword.control.ffi",         foreground: "C586C0" },
  { token: "keyword.control.return",      foreground: "C586C0" },
  { token: "keyword.other.func",          foreground: "569CD6" },
  { token: "keyword.other.trait",         foreground: "569CD6" },
  { token: "keyword.operator",            foreground: "D4D4D4" },
  { token: "keyword.operator.arithmetic", foreground: "D4D4D4" },
  { token: "keyword.operator.logical",    foreground: "D4D4D4" },
  { token: "keyword.operator.assign",     foreground: "D4D4D4" },
  { token: "identifier",                  foreground: "9CDCFE" },
  { token: "delimiter",                   foreground: "D4D4D4" },
];

const $ = (sel) => document.querySelector(sel);
const tree       = $("#tree");
const crumb      = $("#crumb");
const currentPath = $("#currentPath");
const rawLink    = $("#rawLink");
const copyBtn    = $("#copyBtn");
const editorHost = $("#editor");
const emptyMsg   = $("#emptyMsg");

let editor = null;
let allFiles = [];

function groupFiles(files) {
  // Group by top-level directory ("core", "std", "ext"), keeping the order
  // they arrived from the API (already sorted alphabetically by path).
  const groups = new Map();
  for (const f of files) {
    const i = f.path.indexOf("/");
    const top = i < 0 ? "(root)" : f.path.slice(0, i);
    if (!groups.has(top)) groups.set(top, []);
    groups.get(top).push(f);
  }
  return groups;
}

function renderTree(files) {
  tree.innerHTML = "";
  const groups = groupFiles(files);
  for (const [top, items] of groups) {
    const h = document.createElement("div");
    h.className = "group";
    h.textContent = top + "/";
    tree.appendChild(h);
    const ul = document.createElement("ul");
    for (const f of items) {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.href = "?path=" + encodeURIComponent(f.path);
      a.dataset.path = f.path;
      const labelLeaf = f.path.includes("/") ? f.path.slice(f.path.lastIndexOf("/") + 1) : f.path;
      a.innerHTML = "";
      const labelSpan = document.createElement("span");
      labelSpan.textContent = labelLeaf;
      const sizeSpan = document.createElement("span");
      sizeSpan.className = "size";
      sizeSpan.textContent = f.bytes + " B";
      a.appendChild(labelSpan);
      a.appendChild(sizeSpan);
      a.addEventListener("click", (ev) => {
        ev.preventDefault();
        selectPath(f.path, /*push=*/true);
      });
      li.appendChild(a);
      ul.appendChild(li);
    }
    tree.appendChild(ul);
  }
}

function highlightActive(path) {
  for (const a of tree.querySelectorAll("a")) {
    a.classList.toggle("active", a.dataset.path === path);
  }
}

async function ensureEditor() {
  if (editor) return editor;
  const monaco = await window.__monacoReady;
  if (!monaco.languages.getLanguages().some((l) => l.id === "nurl")) {
    monaco.languages.register({ id: "nurl" });
    monaco.languages.setMonarchTokensProvider("nurl", NURL_MONARCH);
    monaco.languages.setLanguageConfiguration("nurl", {
      comments: { lineComment: "//" },
      brackets: [["{","}"],["[","]"],["(",")"]],
    });
    monaco.editor.defineTheme("nurl-dark", {
      base: "vs-dark",
      inherit: true,
      rules: NURL_THEME_RULES,
      colors: {
        "editor.background":        "#161a21",
        "editor.foreground":        "#e6e8ee",
        "editorLineNumber.foreground": "#4b5366",
        "editorCursor.foreground":  "#7cc4ff",
      },
    });
  }
  editor = monaco.editor.create(editorHost, {
    value: "",
    language: "nurl",
    theme: "nurl-dark",
    fontFamily: 'ui-monospace, "SF Mono", Menlo, Consolas, monospace',
    fontSize: 13,
    lineHeight: 1.45,
    minimap: { enabled: true },
    scrollBeyondLastLine: false,
    readOnly: true,
    domReadOnly: true,
    automaticLayout: true,
    smoothScrolling: true,
    tabSize: 2,
    insertSpaces: true,
  });
  return editor;
}

async function selectPath(path, push) {
  if (!path) return;
  const r = await fetch("/stdlib/" + path.split("/").map(encodeURIComponent).join("/"));
  if (!r.ok) {
    crumb.textContent = "load failed: " + path;
    return;
  }
  const j = await r.json();
  const ed = await ensureEditor();
  emptyMsg.style.display = "none";
  editorHost.classList.add("ready");
  ed.setValue(j.source);
  ed.setScrollTop(0);
  currentPath.textContent = "stdlib/" + path;
  crumb.innerHTML = "stdlib / <b>" + path.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</b>";
  rawLink.href = "/stdlib/" + path.split("/").map(encodeURIComponent).join("/");
  rawLink.hidden = false;
  copyBtn.hidden = false;
  document.title = "NURL · " + path;
  highlightActive(path);
  if (push) {
    const url = new URL(window.location.href);
    url.searchParams.set("path", path);
    history.pushState({ path }, "", url);
  }
}

copyBtn.addEventListener("click", async () => {
  if (!editor) return;
  try {
    await navigator.clipboard.writeText(editor.getValue());
    const old = copyBtn.textContent;
    copyBtn.textContent = "copied";
    setTimeout(() => { copyBtn.textContent = old; }, 900);
  } catch (e) { /* permission denied */ }
});

window.addEventListener("popstate", (ev) => {
  const p = new URLSearchParams(window.location.search).get("path");
  if (p) selectPath(p, /*push=*/false);
});

(async function init() {
  try {
    const r = await fetch("/stdlib");
    allFiles = await r.json();
  } catch (e) {
    crumb.textContent = "failed to load /stdlib index";
    return;
  }
  renderTree(allFiles);
  const initialPath = new URLSearchParams(window.location.search).get("path");
  if (initialPath) {
    selectPath(initialPath, /*push=*/false);
  }
})();
</script>
</body>
</html>
"""


class StdlibInfo(BaseModel):
    name: str
    path: str
    bytes: int


class StdlibContent(BaseModel):
    name: str
    source: str
    bytes: int


def _list_stdlib_files() -> list[dict]:
    root = Path(NURL_STDLIB_DIR)
    if not root.is_dir():
        return []
    out: list[dict] = []
    for p in sorted(root.rglob("*.nu")):
        if not p.is_file():
            continue
        rel = p.relative_to(root).as_posix()
        try:
            size = p.stat().st_size
        except OSError:
            continue
        out.append({"name": rel, "path": rel, "bytes": size})
    return out


def _safe_stdlib_path(name: str) -> Path:
    root = Path(NURL_STDLIB_DIR).resolve()
    target = (root / name).resolve()
    if not str(target).startswith(str(root) + os.sep) and target != root:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="invalid stdlib path")
    if not target.is_file() or target.suffix != ".nu":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="stdlib module not found")
    return target


@app.get("/stdlib", response_model=list[StdlibInfo], tags=["stdlib"])
def list_stdlib() -> list[StdlibInfo]:
    """List all bundled NURL stdlib `.nu` modules with sizes."""
    return [StdlibInfo(**e) for e in _list_stdlib_files()]


@app.get("/stdlib/{name:path}", response_model=StdlibContent, tags=["stdlib"])
def get_stdlib_module(name: str) -> StdlibContent:
    """Return the source of a single stdlib module."""
    target = _safe_stdlib_path(name)
    source = target.read_text(encoding="utf-8", errors="replace")
    return StdlibContent(name=name, source=source, bytes=len(source.encode("utf-8")))


@app.get("/stdlib-viewer", response_class=HTMLResponse, tags=["stdlib"],
         include_in_schema=False,
         summary="Browsable Monaco-highlighted viewer for stdlib modules")
def stdlib_viewer() -> HTMLResponse:
    """Standalone read-only viewer page for browsing stdlib `.nu` files.

    Loads Monaco editor from CDN and reuses the playground's NURL Monarch
    grammar. The file list and contents are fetched at runtime from
    `/stdlib` and `/stdlib/{path}`, so this page is a thin shell — no
    server-side templating of source code.
    """
    return HTMLResponse(_STDLIB_VIEWER_HTML)


# Derive the /tests-viewer page from the stdlib viewer template so both UIs
# stay visually identical. Replacements are intentionally narrow strings.
_TESTS_VIEWER_HTML = (
    _STDLIB_VIEWER_HTML
    .replace("NURL Stdlib · Browser", "NURL Tests · Browser")
    .replace("<h1>NURL Stdlib</h1>", "<h1>NURL Tests</h1>")
    .replace(
        "Select a stdlib module on the left to view it.",
        "Select a compiler test on the left to view it.",
    )
    .replace('fetch("/stdlib/"', 'fetch("/tests/"')
    .replace('fetch("/stdlib")', 'fetch("/tests")')
    .replace('"/stdlib/" + path', '"/tests/" + path')
    .replace('"stdlib/" + path', '"compiler/tests/" + path')
    .replace(
        '"stdlib / <b>" + path.replace',
        '"compiler/tests / <b>" + path.replace',
    )
    .replace('rawLink.href = "/stdlib/"', 'rawLink.href = "/tests/"')
    .replace(
        'crumb.textContent = "failed to load /stdlib index"',
        'crumb.textContent = "failed to load /tests index"',
    )
)


@app.get("/tests-viewer", response_class=HTMLResponse, tags=["tests"],
         include_in_schema=False,
         summary="Browsable Monaco-highlighted viewer for compiler tests")
def tests_viewer() -> HTMLResponse:
    """Read-only viewer page for browsing compiler test `.nu` files.

    Same chrome as `/stdlib-viewer`, but lists files under
    `compiler/tests/` and fetches sources from `/tests` and `/tests/{path}`.
    """
    return HTMLResponse(_TESTS_VIEWER_HTML)


# ── License pages ───────────────────────────────────────────────
#
# The repo is dual-licensed under MIT OR Apache-2.0 (see /LICENSE-MIT,
# /LICENSE-APACHE, /NOTICE at the repository root). The runtime image
# copies all three to /opt/nurl/. We surface them through the same doc
# template used by /readme + /grammar so playground users have a clear
# in-app pointer to the licensing terms.

NURL_LICENSE_MIT_PATH    = os.environ.get("NURL_LICENSE_MIT_PATH",    "/opt/nurl/LICENSE-MIT")
NURL_LICENSE_APACHE_PATH = os.environ.get("NURL_LICENSE_APACHE_PATH", "/opt/nurl/LICENSE-APACHE")
NURL_NOTICE_PATH         = os.environ.get("NURL_NOTICE_PATH",         "/opt/nurl/NOTICE")


def _read_text_file(path_str: str, label: str) -> str:
    p = Path(path_str)
    if not p.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"{label} not found")
    return p.read_text(encoding="utf-8", errors="replace")


def _render_license_index(notice_text: str) -> HTMLResponse:
    md_text = (
        "# License\n\n"
        "NURL is **dual-licensed** under either of:\n\n"
        "- [MIT License](/license/mit) (also available [raw](/LICENSE-MIT))\n"
        "- [Apache License, Version 2.0](/license/apache) (also available [raw](/LICENSE-APACHE))\n\n"
        "at your option. SPDX identifier: `MIT OR Apache-2.0`.\n\n"
        "## NOTICE\n\n"
        "```\n" + notice_text.rstrip() + "\n```\n\n"
        "## Contribution\n\n"
        "Unless you explicitly state otherwise, any contribution intentionally "
        "submitted for inclusion in the work by you, as defined in the Apache-2.0 "
        "license, shall be dual-licensed as above, without any additional terms "
        "or conditions.\n"
    )
    html = _md.markdown(
        md_text,
        extensions=["fenced_code", "sane_lists"],
        output_format="html5",
    )
    return HTMLResponse(_render_doc_page(title="License", body_html=html, raw_path="/NOTICE"))


@app.get("/license", response_class=HTMLResponse, tags=["docs"],
         summary="Dual-license overview (MIT OR Apache-2.0)")
def license_index() -> HTMLResponse:
    try:
        notice_text = _read_text_file(NURL_NOTICE_PATH, "NOTICE")
    except HTTPException:
        notice_text = (
            "NURL — Neural Unified Representation Language\n"
            "Dual-licensed under MIT OR Apache-2.0.\n"
        )
    return _render_license_index(notice_text)


@app.get("/license/mit", response_class=HTMLResponse, tags=["docs"],
         summary="Render LICENSE-MIT")
def license_mit_html() -> HTMLResponse:
    text = _read_text_file(NURL_LICENSE_MIT_PATH, "LICENSE-MIT")
    md_text = "# MIT License\n\n```\n" + text.rstrip() + "\n```\n"
    html = _md.markdown(md_text, extensions=["fenced_code"], output_format="html5")
    return HTMLResponse(_render_doc_page(title="MIT License", body_html=html, raw_path="/LICENSE-MIT"))


@app.get("/license/apache", response_class=HTMLResponse, tags=["docs"],
         summary="Render LICENSE-APACHE (Apache 2.0)")
def license_apache_html() -> HTMLResponse:
    text = _read_text_file(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE")
    md_text = "# Apache License, Version 2.0\n\n```\n" + text.rstrip() + "\n```\n"
    html = _md.markdown(md_text, extensions=["fenced_code"], output_format="html5")
    return HTMLResponse(_render_doc_page(title="Apache License 2.0", body_html=html, raw_path="/LICENSE-APACHE"))


@app.get("/LICENSE-MIT", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw LICENSE-MIT text")
def license_mit_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_LICENSE_MIT_PATH, "LICENSE-MIT"))


@app.get("/LICENSE-APACHE", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw LICENSE-APACHE text")
def license_apache_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_LICENSE_APACHE_PATH, "LICENSE-APACHE"))


@app.get("/NOTICE", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw NOTICE text")
def notice_raw() -> PlainTextResponse:
    return PlainTextResponse(_read_text_file(NURL_NOTICE_PATH, "NOTICE"))


# ── Docs: grammar + README ──────────────────────────────────────

_DOC_PAGE_TEMPLATE = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8" />
<title>{title} · NURL</title>
<meta name="viewport" content="width=device-width,initial-scale=1" />
<link rel="icon" type="image/svg+xml" href="/favicon.svg" />
<style>
  :root {{
    --bg:#0f1115; --panel:#161a21; --panel-2:#1b2029; --border:#262c38;
    --fg:#e6e8ee; --fg-dim:#9aa3b2; --accent:#7cc4ff;
  }}
  html,body {{ background:var(--bg); color:var(--fg); margin:0; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif;
         line-height:1.6; }}
  .wrap {{ max-width: 860px; margin: 0 auto; padding: 2rem 1.25rem 4rem; }}
  header.doc-hdr {{ display:flex; align-items:center; gap:.75rem;
      padding:.75rem 1rem; border-bottom:1px solid var(--border);
      background:var(--panel); position:sticky; top:0; z-index:10; }}
  header.doc-hdr a {{ color:var(--accent); text-decoration:none; font-size:.9rem; }}
  header.doc-hdr a:hover {{ text-decoration:underline; }}
  header.doc-hdr .title {{ font-weight:600; }}
  header.doc-hdr .spacer {{ flex:1; }}
  h1,h2,h3,h4 {{ color:#fff; margin-top:2rem; }}
  h1 {{ border-bottom:1px solid var(--border); padding-bottom:.35em; }}
  h2 {{ border-bottom:1px solid var(--border); padding-bottom:.25em; }}
  a {{ color:var(--accent); }}
  code, pre {{ font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }}
  code {{ background:var(--panel-2); padding:.1em .35em; border-radius:4px;
         font-size:.92em; color:#e6e8ee; }}
  pre {{ background:var(--panel); border:1px solid var(--border);
        padding:.85rem 1rem; border-radius:8px; overflow:auto;
        font-size:.85rem; line-height:1.5; }}
  pre code {{ background:transparent; padding:0; }}
  blockquote {{ border-left:3px solid var(--border); margin:1em 0;
              padding:.25rem 1rem; color:var(--fg-dim); background:var(--panel); }}
  table {{ border-collapse:collapse; }}
  th, td {{ border:1px solid var(--border); padding:.4rem .75rem; }}
  th {{ background:var(--panel); }}
  hr {{ border:0; border-top:1px solid var(--border); margin:2rem 0; }}
  img {{ max-width:100%; }}
  ul, ol {{ padding-left: 1.5rem; }}
  /* Pygments highlights — subset tuned for our dark theme. */
  .codehilite .c, .codehilite .c1, .codehilite .cm {{ color:#6A9955; font-style:italic; }}
  .codehilite .k, .codehilite .kd, .codehilite .kr {{ color:#C586C0; }}
  .codehilite .s, .codehilite .s1, .codehilite .s2, .codehilite .sb {{ color:#CE9178; }}
  .codehilite .mi, .codehilite .mf {{ color:#B5CEA8; }}
  .codehilite .nf {{ color:#DCDCAA; }}
  .codehilite .nc, .codehilite .nn {{ color:#4EC9B0; }}
  .codehilite .o {{ color:#D4D4D4; }}
</style>
</head><body>
<header class="doc-hdr">
  <a href="/">← Playground</a>
  <span class="title">{title}</span>
  <div class="spacer"></div>
  <a href="{raw_path}" target="_blank" rel="noopener">raw</a>
</header>
<div class="wrap">{content}</div>
</body></html>
"""


def _render_doc_page(*, title: str, body_html: str, raw_path: str) -> str:
    return _DOC_PAGE_TEMPLATE.format(title=title, content=body_html, raw_path=raw_path)


@app.get("/readme", response_class=HTMLResponse, tags=["docs"],
         summary="Render README.md as HTML")
def readme_html() -> HTMLResponse:
    path = Path(NURL_README_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="README.md not found")
    md_text = path.read_text(encoding="utf-8", errors="replace")
    html = _md.markdown(
        md_text,
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
        output_format="html5",
    )
    return HTMLResponse(_render_doc_page(title="README", body_html=html, raw_path="/readme.md"))


@app.get("/readme.md", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw README.md source")
def readme_raw() -> PlainTextResponse:
    path = Path(NURL_README_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="README.md not found")
    return PlainTextResponse(path.read_text(encoding="utf-8", errors="replace"))


@app.get("/roadmap", response_class=HTMLResponse, tags=["docs"],
         summary="Render ROADMAP.md as HTML")
def roadmap_html() -> HTMLResponse:
    path = Path(NURL_ROADMAP_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ROADMAP.md not found")
    md_text = path.read_text(encoding="utf-8", errors="replace")
    html = _md.markdown(
        md_text,
        extensions=["fenced_code", "tables", "codehilite", "toc", "sane_lists"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
        output_format="html5",
    )
    return HTMLResponse(_render_doc_page(title="Roadmap", body_html=html, raw_path="/roadmap.md"))


@app.get("/roadmap.md", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw ROADMAP.md source")
def roadmap_raw() -> PlainTextResponse:
    path = Path(NURL_ROADMAP_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ROADMAP.md not found")
    return PlainTextResponse(path.read_text(encoding="utf-8", errors="replace"))


@app.get("/gotchas", response_class=HTMLResponse, tags=["docs"],
         summary="Render docs/GOTCHAS.md as HTML")
def gotchas_html() -> HTMLResponse:
    path = Path(NURL_GOTCHAS_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="GOTCHAS.md not found")
    md_text = path.read_text(encoding="utf-8", errors="replace")
    html = _md.markdown(
        md_text,
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
        output_format="html5",
    )
    return HTMLResponse(_render_doc_page(title="Gotchas", body_html=html, raw_path="/gotchas.md"))


@app.get("/gotchas.md", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw docs/GOTCHAS.md source")
def gotchas_raw() -> PlainTextResponse:
    path = Path(NURL_GOTCHAS_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="GOTCHAS.md not found")
    return PlainTextResponse(path.read_text(encoding="utf-8", errors="replace"))


@app.get("/grammar", response_class=HTMLResponse, tags=["docs"],
         summary="Render the current NURL grammar (spec/grammar.ebnf)")
def grammar_html() -> HTMLResponse:
    path = Path(NURL_GRAMMAR_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="grammar.ebnf not found")
    text = path.read_text(encoding="utf-8", errors="replace")
    # Render as a single fenced code block through the markdown pipeline so we
    # reuse the same page chrome as /readme. Language tag `ebnf` gets decent
    # Pygments highlighting.
    md_text = f"# Grammar (`spec/grammar.ebnf`)\n\n```ebnf\n{text}\n```\n"
    html = _md.markdown(
        md_text,
        extensions=["fenced_code", "codehilite"],
        extension_configs={"codehilite": {"guess_lang": False, "css_class": "codehilite"}},
        output_format="html5",
    )
    return HTMLResponse(_render_doc_page(title="Grammar", body_html=html, raw_path="/grammar.ebnf"))


@app.get("/grammar.ebnf", response_class=PlainTextResponse, tags=["docs"],
         summary="Raw grammar.ebnf source")
def grammar_raw() -> PlainTextResponse:
    path = Path(NURL_GRAMMAR_PATH)
    if not path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="grammar.ebnf not found")
    return PlainTextResponse(path.read_text(encoding="utf-8", errors="replace"))


@app.exception_handler(HTTPException)
async def _http_exc_handler(_request, exc: HTTPException):  # noqa: D401
    return JSONResponse(
        status_code=exc.status_code,
        content={"status": "error", "detail": exc.detail},
    )


# ── Static playground ────────────────────────────────────────────
# Served at "/" (index.html) with supporting assets under "/static/*".
if Path(STATIC_DIR).is_dir():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/", include_in_schema=False)
    def _root() -> FileResponse:
        return FileResponse(str(Path(STATIC_DIR) / "index.html"))

    @app.get("/favicon.ico", include_in_schema=False)
    @app.get("/favicon.svg", include_in_schema=False)
    def _favicon() -> FileResponse:
        fav = Path(STATIC_DIR) / "favicon.svg"
        if not fav.is_file():
            raise HTTPException(status_code=404, detail="favicon not found")
        return FileResponse(str(fav), media_type="image/svg+xml")


# ── REST-MCP (plain HTTP companion) ──────────────────────────────
#
# Independent of the real MCP below — same tool/resource/prompt surface,
# but exposed as ordinary GET/POST endpoints under `/rmcp` for clients
# that can't speak Streamable HTTP MCP. Must be included BEFORE the
# catch-all `app.mount("/", ...)` below; otherwise the MCP sub-app
# would shadow `/rmcp/*`.
from app.rest_mcp import router as _rest_mcp_router  # noqa: E402 — post-route include
app.include_router(_rest_mcp_router)


# ── MCP (Model Context Protocol) sub-app ─────────────────────────
#
# Mounted last at "/" as a catch-all fallback so none of the FastAPI
# routes above are shadowed. FastMCP is configured with
# streamable_http_path="/mcp", so the composed URL is
#   http://<host>:8000/mcp
# and — crucially — POST /mcp hits the handler directly, without the
# 307 redirect Starlette's `Mount("/mcp", …)` would issue (which
# strips the request body and breaks MCP clients like Claude Desktop).
from app.mcp_server import mcp as _mcp  # noqa: E402 — post-route mount


class McpInfoResponse(BaseModel):
    url_path: str = Field(..., examples=["/mcp"])
    transport: str = Field(..., examples=["streamable-http"])
    tools: list[str]
    resources: list[str]
    prompts: list[str]
    client_config_example: dict = Field(
        ...,
        description="Drop-in snippet for mcp.json (Claude Desktop, Cursor, "
                    "Windsurf, Zed). Replace the host/port to match your "
                    "deployment.",
    )


@app.get(
    "/mcp-info",
    response_model=McpInfoResponse,
    tags=["mcp"],
    summary="MCP server connection info",
    description=(
        "Describes the co-hosted Model Context Protocol server. "
        "The MCP JSON-RPC endpoint itself lives at `POST /mcp` (Streamable "
        "HTTP transport) but is implemented as an ASGI sub-app, so its "
        "methods are not enumerated in this OpenAPI schema."
    ),
)
def mcp_info(request: Request) -> McpInfoResponse:
    base = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/") or str(request.base_url).rstrip("/")
    return McpInfoResponse(
        url_path="/mcp",
        transport="streamable-http",
        tools=[
            "nurl_build_native", "nurl_build_windows",
            "nurl_build_macos", "nurl_build_wasm",
            "nurl_list_examples", "nurl_read_example",
            "nurl_list_stdlib", "nurl_read_stdlib",
            "nurl_list_tests", "nurl_read_test",
            "nurl_read_grammar", "nurl_read_readme",
            "nurl_read_roadmap", "nurl_read_gotchas",
        ],
        resources=[
            "nurl://grammar", "nurl://readme",
            "nurl://roadmap", "nurl://gotchas",
            "nurl://stdlib/{path}", "nurl://example/{name}",
            "nurl://test/{name}",
        ],
        prompts=["nurl_coding_assistant"],
        client_config_example={
            "mcpServers": {
                "nurl": {
                    "url": base + "/mcp",
                    "transport": "streamable-http",
                }
            }
        },
    )


# ── OAuth 2.0 / OIDC stubs for MCP client compatibility ─────────
#
# Claude Desktop (and similar MCP clients) probe the following
# well-known endpoints even when the server doesn't require auth,
# and some refuse to proceed if Dynamic Client Registration (RFC 7591)
# returns 404 for a remote URL. The MCP Streamable HTTP handler itself
# enforces nothing — auth is a client-side UX concern here — so we
# expose minimal pass-through endpoints that always succeed with a
# dummy client. No tokens are ever validated on /mcp requests.
#
# If you ever want real authentication, replace these with FastMCP's
# built-in `auth_server_provider` and a proper provider implementation.

# NURL_PUBLIC_URL overrides whatever the reverse proxy tells us, for
# deployments where the container can't figure it out (e.g. headers
# aren't forwarded). When unset, we derive the base URL from the
# incoming request — this relies on uvicorn's --proxy-headers flag
# so request.base_url reflects the public https:// URL.
_OAUTH_PUBLIC_URL = os.environ.get("NURL_PUBLIC_URL", "").rstrip("/")


def _public_base_url(request: Request) -> str:
    if _OAUTH_PUBLIC_URL:
        return _OAUTH_PUBLIC_URL
    return str(request.base_url).rstrip("/")


@app.get("/.well-known/oauth-protected-resource", include_in_schema=False)
@app.get("/.well-known/oauth-protected-resource/mcp", include_in_schema=False)
def _oauth_protected_resource_metadata(request: Request):
    # RFC 9728 — tells the client which auth servers (if any) guard
    # this resource. We list ourselves so the client follows up with
    # the auth-server discovery below, and registration/token flow.
    base = _public_base_url(request)
    return JSONResponse({
        "resource": f"{base}/mcp",
        "authorization_servers": [base],
        "bearer_methods_supported": ["header"],
        "scopes_supported": [],
    })


@app.get("/.well-known/oauth-authorization-server", include_in_schema=False)
@app.get("/.well-known/openid-configuration", include_in_schema=False)
def _oauth_auth_server_metadata(request: Request):
    base = _public_base_url(request)
    # RFC 8414 — Authorization Server Metadata. Advertises the minimal
    # set of endpoints needed for an unauthenticated Dynamic-Client-
    # Registration → access-token dance.
    return JSONResponse({
        "issuer": base,
        "authorization_endpoint":    f"{base}/authorize",
        "token_endpoint":             f"{base}/token",
        "registration_endpoint":      f"{base}/register",
        "response_types_supported":  ["code"],
        "grant_types_supported":     ["authorization_code", "client_credentials"],
        "token_endpoint_auth_methods_supported": ["none"],
        "code_challenge_methods_supported":      ["S256", "plain"],
        "scopes_supported":          [],
    })


@app.post("/register", include_in_schema=False)
async def _oauth_register(request: Request):
    # RFC 7591 Dynamic Client Registration — rubber-stamp any request.
    # No secret is returned because token_endpoint_auth_method is "none".
    # We echo back every client-submitted metadata field so strict
    # clients (Claude.ai) recognise the registration as valid.
    body: dict = {}
    try:
        body = await request.json()
    except Exception:
        pass
    # Log the incoming body so we can see what the client actually sent
    # if something goes wrong with the handshake downstream.
    print(f"[oauth/register] body={body!r}", flush=True)

    client_id = f"nurl-mcp-{secrets.token_urlsafe(8)}"
    # Baseline + sensible defaults, then overlay any caller-supplied
    # metadata so it's echoed verbatim.
    response = {
        "client_id": client_id,
        "client_id_issued_at": int(time.time()),
        "grant_types":     ["authorization_code"],
        "response_types":  ["code"],
        "redirect_uris":   [],
        "token_endpoint_auth_method": "none",
    }
    # Pass through any standard DCR metadata field the client sent.
    for key in (
        "redirect_uris", "grant_types", "response_types",
        "token_endpoint_auth_method", "client_name", "client_uri",
        "logo_uri", "scope", "contacts", "tos_uri", "policy_uri",
        "jwks_uri", "jwks", "software_id", "software_version",
        "software_statement", "application_type",
    ):
        if key in body:
            response[key] = body[key]
    return JSONResponse(response, status_code=201)


@app.get("/authorize", include_in_schema=False)
def _oauth_authorize(
    request: Request,
    client_id: str | None = None,
    redirect_uri: str | None = None,
    state: str | None = None,
    code_challenge: str | None = None,
    code_challenge_method: str | None = None,
    response_type: str | None = None,
    scope: str | None = None,
):
    # Instantly redirect back with a dummy authorisation code; no
    # consent UI and no user interaction — effectively "always allow".
    if not redirect_uri:
        raise HTTPException(status_code=400, detail="redirect_uri required")
    from urllib.parse import urlencode
    params = {"code": secrets.token_urlsafe(16)}
    if state:
        params["state"] = state
    sep = "&" if "?" in redirect_uri else "?"
    return Response(status_code=302, headers={"Location": redirect_uri + sep + urlencode(params)})


@app.post("/token", include_in_schema=False)
async def _oauth_token(request: Request):
    # Accepts any grant — returns an opaque bearer the /mcp handler
    # never actually checks. Long expiry so clients don't refresh.
    return JSONResponse({
        "access_token": secrets.token_urlsafe(32),
        "token_type":   "Bearer",
        "expires_in":   60 * 60 * 24 * 365,
        "scope":        "",
    })


app.mount("/", _mcp.streamable_http_app())


# MCP client-compatibility shim for the FastMCP Streamable HTTP endpoint.
#
# Two quirks are smoothed over here so third-party clients (Claude
# Desktop, some IDE bridges) can connect without a custom transport:
#
#   1. FastMCP mounts its handler via `Mount("/mcp", …)`, which makes
#      Starlette 307-redirect bare `/mcp` to `/mcp/`. That redirect
#      drops the POST body and many clients abandon the handshake.
#      We rewrite the scope path in place before routing, so `/mcp`
#      and `/mcp/` are both accepted without ever emitting a redirect.
#
#   2. The Streamable HTTP spec (and thus the mcp SDK) requires the
#      client's `Accept` header to list BOTH `application/json` and
#      `text/event-stream`; otherwise the server answers 406. Older
#      Claude builds only send one of the two. We transparently add
#      whichever is missing so both the strict mcp check and the
#      client's actual expectations are satisfied.
@app.middleware("http")
async def _mcp_client_compat(request: Request, call_next):
    path = request.scope.get("path", "")
    if path == "/mcp" or path.startswith("/mcp/"):
        if path == "/mcp":
            request.scope["path"] = "/mcp/"
            request.scope["raw_path"] = b"/mcp/"

        # Normalise the Accept header in the raw ASGI headers list so
        # the downstream mcp SDK (which reads request.headers) sees it.
        headers = list(request.scope.get("headers") or [])
        accept_val = ""
        for i, (k, v) in enumerate(headers):
            if k == b"accept":
                accept_val = v.decode("latin-1")
                headers.pop(i)
                break
        parts = [p.strip() for p in accept_val.split(",") if p.strip()]
        has_json = any(p.startswith("application/json") for p in parts)
        has_sse  = any(p.startswith("text/event-stream") for p in parts)
        if not has_json:
            parts.append("application/json")
        if not has_sse:
            parts.append("text/event-stream")
        headers.append((b"accept", ", ".join(parts).encode("latin-1")))
        request.scope["headers"] = headers

    return await call_next(request)
