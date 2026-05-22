# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""NURL HTTP API.

Minimal FastAPI service exposing:
  - GET  /health         liveness probe
  - POST /build          compiles NURL source to a native Linux ELF
  - POST /build_windows  cross-compiles NURL source to a Windows .exe (zig cc)
  - POST /build_macos    cross-compiles NURL source to a macOS Mach-O binary (zig cc)
  - POST /build_wasm     compiles NURL source to wasm32-wasi WebAssembly (zig cc)

Swagger UI is served automatically at /docs, ReDoc at /redoc,
and the OpenAPI schema at /openapi.json.
"""
from __future__ import annotations

import base64
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
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
from app.artifacts import ArtifactStore, BuildArtifact, sanitize_basename

NURLC_PATH = os.environ.get("NURLC_PATH", "/opt/nurl/build/nurlc")
# wasm32-wasi is produced by `zig cc -target wasm32-wasi` (NURL_ZIG, defined
# below) — Zig bundles wasi-libc, so no separate WASI SDK is needed and the
# build runs natively on any host arch.
WASM_TARGET = os.environ.get("NURL_WASM_TARGET", "wasm32-wasi")
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

# Native build pipeline (mirrors `zig build nurl -- ...`): plain clang + stdlib/runtime.o.
# The container points this at clang-16 (NURL_NATIVE_CLANG); Debian bookworm's
# stock `clang` is clang-14, which still enforces typed pointers and rejects
# the opaque-pointer IR modern nurlc emits.
NATIVE_CLANG   = os.environ.get(
    "NURL_NATIVE_CLANG",
    "/usr/bin/clang" if Path("/usr/bin/clang").exists() else "clang",
)
# `zig build` emits runtime.o as LLVM bitcode (it builds the compiler under
# `-flto`); a stock `clang` + GNU `ld` link — which is what /build does —
# rejects bitcode with "file format not recognized". `zig build` also writes
# a plain-ELF `runtime.native.o` next to it for exactly this link path, so
# prefer that when present and only fall back to runtime.o otherwise.
def _default_runtime_o() -> str:
    native = "/opt/nurl/stdlib/runtime.native.o"
    return native if Path(native).is_file() else "/opt/nurl/stdlib/runtime.o"

RUNTIME_O      = os.environ.get("NURL_RUNTIME_O",  _default_runtime_o())
CANVAS_O       = os.environ.get("NURL_CANVAS_O",   "/opt/nurl/stdlib/canvas.o")
NURL_LINK_HELPER = os.environ.get("NURL_LINK_HELPER", "/opt/nurl/build/nurl-build")

# Windows cross-compile pipeline. `zig cc -target x86_64-windows-gnu` consumes
# the LLVM IR in one step: it bundles the mingw-w64 CRT, libgcc equivalents,
# and lld, and links the prebuilt Windows-native `runtime.win.o` (compiled by
# the Dockerfile build stage with the same zig target). No external mingw-w64
# toolchain is involved. This path is fully separate from the Linux/wasm
# pipelines — neither is touched.
WINDOWS_TARGET = os.environ.get("NURL_WINDOWS_TARGET", "x86_64-windows-gnu")
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
_artifact_store = ArtifactStore(OUTPUT_DIR, DOWNLOAD_TTL_SEC)

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


def _link_helper_available() -> bool:
    return _is_executable(NURL_LINK_HELPER)


def _nurlc_available() -> bool:
    return _is_executable(NURLC_PATH) or shutil.which("nurlc") is not None


def _wasi_toolchain_available() -> bool:
    return (
        (shutil.which(NURL_ZIG) is not None or _is_executable(NURL_ZIG))
        and Path(RUNTIME_WASM_O).is_file()
    )


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


def _run(
    cmd: list[str],
    *,
    cwd: str,
    stdin: bytes | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(
            cmd,
            cwd=cwd,
            input=stdin,
            capture_output=True,
            timeout=BUILD_TIMEOUT_SEC,
            check=False,
            env=env,
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
                f"wasm toolchain unavailable "
                f"(zig={NURL_ZIG}, runtime={RUNTIME_WASM_O})"
            ),
        )
    if not _link_helper_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"link helper not found at '{NURL_LINK_HELPER}'",
        )

    return _run_api_build_wasm_helper(req)


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
        description="Clang optimisation flag. Defaults to -O2 (matches `zig build nurl`).",
        examples=["-O0", "-O2"],
    )


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

def _run_api_build_helper(
    req: BuildRequest,
    request: Request,
    *,
    kind: Literal["native", "windows", "macos"],
    driver: str,
    runtime: str,
    target: str | None,
    binary_media_type: str,
    executable_artifact: bool,
    canvas_obj: str | None = None,
    canvas_sdl2_marker: str | None = None,
) -> BuildResponse:
    _artifact_store.gc()

    opt_flag = req.opt if req.opt and req.opt.startswith("-O") else "-O2"
    output_root = _artifact_store.output_dir
    output_root.mkdir(parents=True, exist_ok=True)
    build_prefix = {
        "native": "build",
        "windows": "buildwin",
        "macos": "buildmac",
    }[kind]
    build_dir = output_root / f"{build_prefix}-{uuid.uuid4().hex[:12]}"
    build_dir.mkdir(parents=True, exist_ok=False)

    with tempfile.TemporaryDirectory(prefix=f"nurl-build-{kind}-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{sanitize_basename(req.filename)}.nu"
        nu_path.write_bytes(req.source.encode("utf-8"))

        helper_cmd = [
            NURL_LINK_HELPER,
            "api-build",
            "--kind", kind,
            "--root", NURL_WORK_ROOT,
            "--src", str(nu_path),
            "--build-dir", str(build_dir),
            "--driver", driver,
            "--runtime", runtime,
            "--opt", opt_flag,
        ]
        if req.filename:
            helper_cmd += ["--filename", req.filename]
        if target:
            helper_cmd += ["--target", target]
        if canvas_obj:
            helper_cmd += ["--canvas-obj", canvas_obj]
        if canvas_sdl2_marker:
            helper_cmd += ["--canvas-sdl2-marker", canvas_sdl2_marker]

        helper_proc = _run(helper_cmd, cwd=str(tmpdir))

    helper_stdout = helper_proc.stdout.decode("utf-8", "replace")
    helper_stderr = helper_proc.stderr.decode("utf-8", "replace").strip()
    if helper_proc.returncode != 0:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=helper_stderr or helper_stdout or f"{kind} api-build helper failed",
        )

    try:
        payload = json.loads(helper_stdout or "{}")
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"{kind} api-build helper returned invalid JSON",
        ) from e

    http_status = int(payload.get("http_status", 200))
    if http_status != 200:
        raise HTTPException(
            status_code=http_status,
            detail=payload.get("fatal_detail")
            or payload.get("stderr")
            or payload.get("message")
            or f"{kind} build failed",
        )

    ll_artifact = None
    if payload.get("ll_path"):
        ll_artifact = _artifact_store.register_build_artifact(
            Path(payload["ll_path"]),
            "text/plain",
            request,
        )

    binary_artifact = None
    if payload.get("binary_path"):
        binary_artifact = _artifact_store.register_build_artifact(
            Path(payload["binary_path"]),
            binary_media_type,
            request,
            executable=executable_artifact,
        )

    nurlc_stderr = str(payload.get("nurlc_stderr") or "")
    return BuildResponse(
        status=str(payload.get("status") or "error"),
        message=str(payload.get("message") or f"{kind} build failed"),
        filename=req.filename,
        uses_canvas=bool(payload.get("uses_canvas")),
        nurlc_returncode=int(payload.get("nurlc_returncode", 0)),
        nurlc_stdout_bytes=int(payload.get("nurlc_stdout_bytes", 0)),
        nurlc_stderr=nurlc_stderr,
        clang_returncode=payload.get("clang_returncode"),
        clang_stdout=payload.get("clang_stdout") or None,
        clang_stderr=payload.get("clang_stderr") or None,
        stdout=str(payload.get("stdout") or ""),
        stderr=str(payload.get("stderr") or ""),
        nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
        ll_artifact=ll_artifact,
        binary_artifact=binary_artifact,
    )


def _run_api_build_wasm_helper(req: BuildWasmRequest):
    basename = sanitize_basename(req.filename)

    with tempfile.TemporaryDirectory(prefix="nurl-build-wasm-") as tmp:
        tmpdir = Path(tmp)
        nu_path = tmpdir / f"{basename}.nu"
        nu_path.write_bytes(req.source.encode("utf-8"))

        helper_cmd = [
            NURL_LINK_HELPER,
            "api-build-wasm",
            "--root", NURL_WORK_ROOT,
            "--src", str(nu_path),
            "--build-dir", str(tmpdir),
            "--target", WASM_TARGET,
            "--runtime", RUNTIME_WASM_O,
            "--canvas-obj", CANVAS_WASM_O,
            "--audio-obj", AUDIO_WASM_O,
            "--zig-driver", f"{NURL_ZIG} cc",
            "--wasm-opt", WASM_OPT,
        ]
        if req.filename:
            helper_cmd += ["--filename", req.filename]

        helper_proc = _run(helper_cmd, cwd=str(tmpdir))
        helper_stdout = helper_proc.stdout.decode("utf-8", "replace")
        helper_stderr = helper_proc.stderr.decode("utf-8", "replace").strip()
        if helper_proc.returncode != 0:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=helper_stderr or helper_stdout or "wasm api-build helper failed",
            )

        try:
            payload = json.loads(helper_stdout or "{}")
        except json.JSONDecodeError as e:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="wasm api-build helper returned invalid JSON",
            ) from e

        http_status = int(payload.get("http_status", 200))
        if http_status != 200:
            if payload.get("error_stage"):
                nurlc_stderr = str(payload.get("error_nurlc_stderr") or "")
                detail = {
                    "stage": payload.get("error_stage"),
                    "returncode": payload.get("error_returncode"),
                    "stderr": payload.get("error_stderr") or "",
                }
                if nurlc_stderr:
                    detail["nurlc_stderr"] = nurlc_stderr
                    detail["errors"] = [d.model_dump() for d in parse_nurlc_diagnostics(nurlc_stderr)]
                raise HTTPException(status_code=http_status, detail=detail)
            raise HTTPException(
                status_code=http_status,
                detail=payload.get("error_message")
                or payload.get("message")
                or "wasm build failed",
            )

        wasm_path = Path(payload["wasm_path"])
        wasm_bytes = wasm_path.read_bytes()
        uses_canvas = bool(payload.get("uses_canvas"))
        uses_audio = bool(payload.get("uses_audio"))

        if req.return_format == "binary":
            return Response(
                content=wasm_bytes,
                media_type="application/wasm",
                headers={
                    "Content-Disposition": f'attachment; filename="{basename}.wasm"',
                    "X-Nurl-Uses-Canvas": "1" if uses_canvas else "0",
                    "X-Nurl-Uses-Audio": "1" if uses_audio else "0",
                },
            )

        llvm_ir = None
        if req.emit_ll and payload.get("raw_ll_path"):
            llvm_ir = Path(payload["raw_ll_path"]).read_text("utf-8", "replace")

        nurlc_stderr = str(payload.get("nurlc_stderr") or "")
        return BuildWasmResponse(
            status=str(payload.get("status") or "error"),
            message=str(payload.get("message") or "wasm build failed"),
            filename=req.filename,
            wasm_base64=base64.b64encode(wasm_bytes).decode("ascii"),
            wasm_bytes=len(wasm_bytes),
            nurlc_stderr=nurlc_stderr or None,
            nurlc_errors=parse_nurlc_diagnostics(nurlc_stderr),
            clang_stderr=(payload.get("clang_stderr") or None),
            llvm_ir=llvm_ir,
            uses_canvas=uses_canvas,
            uses_audio=uses_audio,
        )


@app.post(
    "/build",
    response_model=BuildResponse,
    tags=["build"],
    summary="Compile NURL source to a native binary (mirrors `zig build nurl`)",
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

    Pipeline (identical to `zig build nurl -- ...`):
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
    if not _link_helper_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"link helper not found at '{NURL_LINK_HELPER}'",
        )
    # An LLVM-bitcode runtime.o (`zig build`'s -flto artifact) would only fail
    # deep in the link with a cryptic ld "file format not recognized". Catch
    # it here — it means the image lacks the plain-ELF runtime.native.o.
    if Path(RUNTIME_O).open("rb").read(4) == b"BC\xc0\xde":
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"native runtime object {RUNTIME_O} is LLVM bitcode, not an "
                "ELF object — GNU ld cannot link it. Rebuild the image so "
                "`zig build` produces stdlib/runtime.native.o."
            ),
        )

    return _run_api_build_helper(
        req,
        request,
        kind="native",
        driver=NATIVE_CLANG,
        runtime=RUNTIME_O,
        target=None,
        binary_media_type="application/octet-stream",
        executable_artifact=True,
        canvas_obj=CANVAS_O,
        canvas_sdl2_marker=CANVAS_SDL2_MARKER,
    )


# ── Windows cross-compile (POST /build_windows) ──────────────────
#
# Mirrors /build but routes through `zig cc -target x86_64-windows-gnu` to
# produce a PE/COFF .exe. The pipeline is intentionally a copy rather than a
# flag on /build — keeps the Linux ELF path untouched and lets the Windows
# path evolve (extra link flags, future SDL2-windows support) without risking
# regressions on the well-trodden Linux build.
#
# canvas/audio FFI is rejected up-front: the Windows-side SDL2 and
# microphone bridges aren't compiled into the container.

@app.post(
    "/build_windows",
    response_model=BuildResponse,
    tags=["build"],
    summary="Cross-compile NURL source to a Windows .exe (zig cc)",
    responses={
        200: {"description": "Compilation attempted; see stdout/stderr and artifacts."},
        400: {"description": "Empty source, oversized source, or unsupported FFI."},
        500: {"description": "zig toolchain unavailable."},
        504: {"description": "Compilation timed out."},
    },
)
def build_windows(req: BuildRequest, request: Request) -> BuildResponse:
    """Compile NURL source to a Windows x86_64 .exe via `zig cc`.

    Pipeline:
      1. Write `source` to a temp `.nu` file.
      2. `nurlc <file.nu>` → LLVM IR (`.ll`).
      3. `zig cc -target x86_64-windows-gnu -O2 <ll> runtime.win.o -o <exe>`.

    The runtime is a precompiled `runtime.win.o` produced once at image build
    time with the same zig target. Zig bundles the mingw-w64 CRT, libgcc
    equivalents, and lld, so the compile + link happen in one invocation with
    no external mingw-w64 toolchain to coordinate.
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
    # `zig cc -target x86_64-windows-gnu` is a single-step driver: it bundles
    # the mingw-w64 CRT, libgcc equivalents, and lld, so no separate mingw-w64
    # toolchain is required and the link happens in one invocation.
    if shutil.which(NURL_ZIG) is None and not _is_executable(NURL_ZIG):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                f"zig not found at '{NURL_ZIG}'. "
                "Install Zig and rebuild the container."
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
    if not _link_helper_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"link helper not found at '{NURL_LINK_HELPER}'",
        )

    return _run_api_build_helper(
        req,
        request,
        kind="windows",
        driver=f"{NURL_ZIG} cc",
        runtime=RUNTIME_WIN_O,
        target=WINDOWS_TARGET,
        binary_media_type="application/vnd.microsoft.portable-executable",
        executable_artifact=False,
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
    if not _link_helper_available():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"link helper not found at '{NURL_LINK_HELPER}'",
        )

    return _run_api_build_helper(
        req,
        request,
        kind="macos",
        driver=f"{NURL_ZIG} cc",
        runtime=RUNTIME_MAC_O,
        target=MACOS_TARGET,
        binary_media_type="application/x-mach-binary",
        executable_artifact=True,
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
    _artifact_store.gc()
    entry = _artifact_store.get(token)
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
