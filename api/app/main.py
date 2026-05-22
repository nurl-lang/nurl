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
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from typing import Literal

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

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


# ── Read-only content routes ─────────────────────────────────────
# Examples/tests/stdlib/docs/license browsing and MCP self-description
# live in a separate router so this module stays focused on build APIs.
from app.content_routes import router as _content_router  # noqa: E402
app.include_router(_content_router)


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
from app.mcp_compat import mcp_client_compat_middleware, router as _mcp_compat_router  # noqa: E402
app.include_router(_mcp_compat_router)


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

app.mount("/", _mcp.streamable_http_app())
app.middleware("http")(mcp_client_compat_middleware)
