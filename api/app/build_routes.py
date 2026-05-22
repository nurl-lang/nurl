# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Build API routes, schemas, and helper orchestration."""

from __future__ import annotations

import base64
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException, Request, Response, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.artifacts import ArtifactStore, BuildArtifact, sanitize_basename


@dataclass(frozen=True)
class BuildConfig:
    nurlc_path: str
    wasm_target: str
    runtime_wasm_o: str
    canvas_wasm_o: str
    audio_wasm_o: str
    wasm_opt: str
    nurl_work_root: str
    build_timeout_sec: int
    max_source_bytes: int
    native_clang: str
    runtime_o: str
    canvas_o: str
    link_helper: str
    windows_target: str
    runtime_win_o: str
    nurl_zig: str
    macos_target: str
    runtime_mac_o: str
    canvas_sdl2_marker: str
    output_dir: str
    download_ttl_sec: int


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
    """Structured representation of a single nurlc error line."""

    file: str
    line: int
    col: int
    message: str


_DIAG_RE = re.compile(r"^(?P<file>.+?):(?P<line>\d+):(?P<col>\d+):\s*(?P<msg>.+)$")


def parse_nurlc_diagnostics(stderr: str) -> list[NurlcDiagnostic]:
    """Extract structured diagnostics from nurlc stderr."""

    diags: list[NurlcDiagnostic] = []
    for raw in (stderr or "").splitlines():
        match = _DIAG_RE.match(raw.strip())
        if not match:
            continue
        try:
            diags.append(
                NurlcDiagnostic(
                    file=match.group("file"),
                    line=int(match.group("line")),
                    col=int(match.group("col")),
                    message=match.group("msg").strip(),
                )
            )
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
        ...,
        description=(
            "Combined stdout from nurlc + clang (nurlc stdout is the LLVM IR; "
            "it's omitted here to keep the payload small — use the .ll download)."
        ),
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


def _is_executable(path: str) -> bool:
    target = Path(path)
    return target.is_file() and os.access(target, os.X_OK)


def _is_bitcode_object(path: str) -> bool:
    with Path(path).open("rb") as handle:
        return handle.read(4) == b"BC\xc0\xde"


def create_build_router(config: BuildConfig) -> APIRouter:
    router = APIRouter()
    artifact_store = ArtifactStore(config.output_dir, config.download_ttl_sec)

    def _link_helper_available() -> bool:
        return _is_executable(config.link_helper)

    def _nurlc_available() -> bool:
        return _is_executable(config.nurlc_path) or shutil.which("nurlc") is not None

    def _zig_available() -> bool:
        return shutil.which(config.nurl_zig) is not None or _is_executable(config.nurl_zig)

    def _validate_source(source: str) -> bytes:
        if not source.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="source must not be empty",
            )
        source_bytes = source.encode("utf-8")
        if len(source_bytes) > config.max_source_bytes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"source exceeds {config.max_source_bytes} bytes",
            )
        return source_bytes

    def _require_nurlc() -> None:
        if not _nurlc_available():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"nurlc not found at {config.nurlc_path}",
            )

    def _require_link_helper() -> None:
        if not _link_helper_available():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"link helper not found at '{config.link_helper}'",
            )

    def _require_wasm_toolchain() -> None:
        _require_nurlc()
        if not (_zig_available() and Path(config.runtime_wasm_o).is_file()):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"wasm toolchain unavailable "
                    f"(zig={config.nurl_zig}, runtime={config.runtime_wasm_o})"
                ),
            )
        _require_link_helper()

    def _require_native_toolchain() -> None:
        _require_nurlc()
        if shutil.which(config.native_clang) is None and not _is_executable(config.native_clang):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"native clang not found at '{config.native_clang}'",
            )
        if not Path(config.runtime_o).is_file():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"native runtime object missing at {config.runtime_o}",
            )
        _require_link_helper()
        if _is_bitcode_object(config.runtime_o):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"native runtime object {config.runtime_o} is LLVM bitcode, not an "
                    "ELF object — GNU ld cannot link it. Rebuild the image so "
                    "`zig build` produces stdlib/runtime.native.o."
                ),
            )

    def _require_windows_toolchain() -> None:
        _require_nurlc()
        if not _zig_available():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"zig not found at '{config.nurl_zig}'. "
                    "Install Zig and rebuild the container."
                ),
            )
        if not Path(config.runtime_win_o).is_file():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"Windows runtime object missing at {config.runtime_win_o}. "
                    "Rebuild the container so the build stage produces runtime.win.o."
                ),
            )
        _require_link_helper()

    def _require_macos_toolchain() -> None:
        _require_nurlc()
        if not _zig_available():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"zig toolchain not found at '{config.nurl_zig}'. "
                    "Rebuild the container so the build stage installs zig."
                ),
            )
        if not Path(config.runtime_mac_o).is_file():
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"macOS runtime object missing at {config.runtime_mac_o}. "
                    "Rebuild the container so the build stage produces runtime.mac.o."
                ),
            )
        _require_link_helper()

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
                timeout=config.build_timeout_sec,
                check=False,
                env=env,
            )
        except subprocess.TimeoutExpired as exc:
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail=f"{cmd[0]} timed out after {config.build_timeout_sec}s",
            ) from exc
        except FileNotFoundError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"executable not found: {cmd[0]}",
            ) from exc

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
        artifact_store.gc()

        opt_flag = req.opt if req.opt and req.opt.startswith("-O") else "-O2"
        output_root = artifact_store.output_dir
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
                config.link_helper,
                "api-build",
                "--kind",
                kind,
                "--root",
                config.nurl_work_root,
                "--src",
                str(nu_path),
                "--build-dir",
                str(build_dir),
                "--driver",
                driver,
                "--runtime",
                runtime,
                "--opt",
                opt_flag,
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
        except json.JSONDecodeError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"{kind} api-build helper returned invalid JSON",
            ) from exc

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
            ll_artifact = artifact_store.register_build_artifact(
                Path(payload["ll_path"]),
                "text/plain",
                request,
            )

        binary_artifact = None
        if payload.get("binary_path"):
            binary_artifact = artifact_store.register_build_artifact(
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
                config.link_helper,
                "api-build-wasm",
                "--root",
                config.nurl_work_root,
                "--src",
                str(nu_path),
                "--build-dir",
                str(tmpdir),
                "--target",
                config.wasm_target,
                "--runtime",
                config.runtime_wasm_o,
                "--canvas-obj",
                config.canvas_wasm_o,
                "--audio-obj",
                config.audio_wasm_o,
                "--zig-driver",
                f"{config.nurl_zig} cc",
                "--wasm-opt",
                config.wasm_opt,
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
            except json.JSONDecodeError as exc:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="wasm api-build helper returned invalid JSON",
                ) from exc

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
                        detail["errors"] = [
                            diag.model_dump()
                            for diag in parse_nurlc_diagnostics(nurlc_stderr)
                        ]
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

    @router.post(
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
        _validate_source(req.source)
        _require_wasm_toolchain()
        return _run_api_build_wasm_helper(req)

    @router.post(
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
        _validate_source(req.source)
        _require_native_toolchain()
        return _run_api_build_helper(
            req,
            request,
            kind="native",
            driver=config.native_clang,
            runtime=config.runtime_o,
            target=None,
            binary_media_type="application/octet-stream",
            executable_artifact=True,
            canvas_obj=config.canvas_o,
            canvas_sdl2_marker=config.canvas_sdl2_marker,
        )

    @router.post(
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
        _validate_source(req.source)
        _require_windows_toolchain()
        return _run_api_build_helper(
            req,
            request,
            kind="windows",
            driver=f"{config.nurl_zig} cc",
            runtime=config.runtime_win_o,
            target=config.windows_target,
            binary_media_type="application/vnd.microsoft.portable-executable",
            executable_artifact=False,
        )

    @router.post(
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
        _validate_source(req.source)
        _require_macos_toolchain()
        return _run_api_build_helper(
            req,
            request,
            kind="macos",
            driver=f"{config.nurl_zig} cc",
            runtime=config.runtime_mac_o,
            target=config.macos_target,
            binary_media_type="application/x-mach-binary",
            executable_artifact=True,
        )

    @router.get(
        "/download/{token}",
        tags=["build"],
        summary="Download a build artifact (.ll or native binary) produced by /build",
        responses={
            200: {"description": "Artifact stream."},
            404: {"description": "Unknown or expired token."},
        },
    )
    def download_artifact(token: str) -> FileResponse:
        artifact_store.gc()
        entry = artifact_store.get(token)
        if entry is None or not entry.path.is_file():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="unknown or expired token",
            )
        return FileResponse(
            path=str(entry.path),
            media_type=entry.media_type,
            filename=entry.filename,
        )

    return router
