# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
"""Shared MCP catalog metadata for both /mcp and /rmcp transports."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


NURL_STDLIB_DIR = os.environ.get("NURL_STDLIB_DIR", "/opt/nurl/stdlib")
NURL_EXAMPLES_DIR = os.environ.get("NURL_EXAMPLES_DIR", "/opt/nurl/examples")
NURL_TESTS_DIR = os.environ.get("NURL_TESTS_DIR", "/opt/nurl/compiler/tests")
NURL_GRAMMAR_PATH = os.environ.get("NURL_GRAMMAR_PATH", "/opt/nurl/spec/grammar.ebnf")
NURL_README_PATH = os.environ.get("NURL_README_PATH", "/opt/nurl/README.md")
NURL_ROADMAP_PATH = os.environ.get("NURL_ROADMAP_PATH", "/opt/nurl/ROADMAP.md")
NURL_GOTCHAS_PATH = os.environ.get("NURL_GOTCHAS_PATH", "/opt/nurl/docs/GOTCHAS.md")


MCP_INSTRUCTIONS = (
    "NURL language toolchain. Use `nurl_build_native` (Linux ELF), "
    "`nurl_build_windows` (Windows .exe via zig cc), "
    "`nurl_build_macos` (macOS Mach-O via zig cc), or "
    "`nurl_build_wasm` (wasm32-wasi via zig cc) to compile source. The language uses a "
    "terse prefix notation: functions are declared with "
    "`@ name → ret_ty { body }`, return via `^ expr`, and call "
    "functions with parenthesised prefix form like `( puts `hello` )`. "
    "Read `nurl://grammar` and `nurl://readme` for the full spec; "
    "fetch working examples via `nurl_read_example`."
)

REST_INSTRUCTIONS = (
    "NURL language toolchain over plain REST (companion to /mcp). "
    "Build with `nurl_build_native` (Linux ELF), `nurl_build_windows` "
    "(.exe via zig cc), `nurl_build_macos` (Mach-O via zig cc), "
    "or `nurl_build_wasm`. NURL syntax is terse "
    "prefix: declare with `@ name → ret_ty { body }`, return via "
    "`^ expr`, call with `( fname args… )`, strings in backticks. "
    "Read `nurl://grammar` and `nurl://readme` for the full spec; "
    "fetch working examples via `nurl_read_example`. Validate generated "
    "code by running a build tool and checking `nurlc_errors`."
)


class ToolSpec(BaseModel):
    name: str
    description: str
    input_schema: dict[str, Any] = Field(
        ...,
        description="JSON Schema for the POST body of /rmcp/tools/{name}.",
    )


class ResourceSpec(BaseModel):
    uri: str
    name: str
    description: str
    mime_type: str = "text/plain"


class PromptSpec(BaseModel):
    name: str
    description: str
    arguments: list[dict[str, Any]] = Field(default_factory=list)


BUILD_REQ_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "source": {"type": "string", "description": "NURL source code."},
        "filename": {"type": "string", "description": "Logical name (default main.nu)."},
    },
    "required": ["source"],
    "additionalProperties": False,
}

BUILD_WASM_REQ_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "source": {"type": "string"},
        "filename": {"type": "string"},
        "emit_ll": {"type": "boolean", "description": "Include LLVM IR in response."},
    },
    "required": ["source"],
    "additionalProperties": False,
}

NAME_ARG_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {"name": {"type": "string"}},
    "required": ["name"],
    "additionalProperties": False,
}

NO_ARGS_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {},
    "additionalProperties": False,
}


TOOLS: list[ToolSpec] = [
    ToolSpec(
        name="nurl_build_native",
        description=(
            "Compile NURL source to a native x86_64 Linux ELF binary. "
            "Returns build status, nurlc+clang return codes and stderr, "
            "plus download URLs for the generated `.ll` (LLVM IR) and "
            "the binary. Equivalent to `POST /build`."
        ),
        input_schema=BUILD_REQ_SCHEMA,
    ),
    ToolSpec(
        name="nurl_build_windows",
        description=(
            "Cross-compile NURL source to a Windows x86_64 .exe via zig cc "
            "(x86_64-windows-gnu). Returns build status, nurlc + zig cc return "
            "codes and stderr, plus download URLs for the generated `.ll` (LLVM "
            "IR) and the `.exe`. canvas/audio FFI is not supported on this "
            "target. Equivalent to `POST /build_windows`."
        ),
        input_schema=BUILD_REQ_SCHEMA,
    ),
    ToolSpec(
        name="nurl_build_macos",
        description=(
            "Cross-compile NURL source to a macOS x86_64 Mach-O binary via zig cc. "
            "Returns build status, nurlc+zig return codes and stderr, plus download "
            "URLs for the generated `.ll` (LLVM IR) and the binary. The result "
            "links only libSystem — canvas/audio FFI and libcurl-backed HTTP are "
            "not supported on this target. The binary is unsigned; users must "
            "clear the Gatekeeper quarantine attribute before running it. "
            "Equivalent to `POST /build_macos`."
        ),
        input_schema=BUILD_REQ_SCHEMA,
    ),
    ToolSpec(
        name="nurl_build_wasm",
        description=(
            "Compile NURL source to a wasm32-wasi WebAssembly module. "
            "Returns the wasm bytes (base64) plus compile logs. Suitable "
            "for running in-browser via a WASI shim or with wasmtime. "
            "Equivalent to `POST /build_wasm`."
        ),
        input_schema=BUILD_WASM_REQ_SCHEMA,
    ),
    ToolSpec(
        name="nurl_list_examples",
        description=(
            "List bundled NURL example programs. Each entry has `name`, "
            "`path` and `bytes`. Use `nurl_read_example` to fetch the "
            "source of a specific one."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_example",
        description=(
            "Read the source of a bundled NURL example by name "
            "(e.g. 'enigma.nu' or 'calculator.nu'). Returns the full "
            "source as a string."
        ),
        input_schema=NAME_ARG_SCHEMA,
    ),
    ToolSpec(
        name="nurl_list_stdlib",
        description=(
            "List NURL stdlib modules (.nu files under the stdlib "
            "directory). Return relative paths; read any one via the "
            "`nurl://stdlib/{path}` resource."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_stdlib",
        description=(
            "Read the source of a NURL stdlib module by relative path "
            "(e.g. 'core/option.nu' or 'std/string.nu'). Returns the full "
            "source as a string."
        ),
        input_schema=NAME_ARG_SCHEMA,
    ),
    ToolSpec(
        name="nurl_list_tests",
        description=(
            "List bundled NURL compiler test programs (.nu files under "
            "compiler/tests). Compiler has passed all of them. Each entry has `name`, `path` and `bytes`. "
            "Use `nurl_read_test` to fetch the source of a specific one."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_test",
        description=(
            "Read the source of a bundled NURL compiler test by name "
            "(e.g. 'generic_struct.nu' or 'string_mvp3.nu'). Returns the "
            "full source as a string."
        ),
        input_schema=NAME_ARG_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_grammar",
        description=(
            "Read the authoritative NURL grammar (EBNF) from "
            "`spec/grammar.ebnf`. Equivalent to the `nurl://grammar` resource, "
            "exposed as a tool for clients that don't fetch resources."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_readme",
        description=(
            "Read the project README (`README.md`) covering NURL design, "
            "usage and toolchain. Equivalent to the `nurl://readme` resource."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_roadmap",
        description=(
            "Read the project ROADMAP (`ROADMAP.md`) covering planned features "
            "and direction. Equivalent to the `nurl://roadmap` resource."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
    ToolSpec(
        name="nurl_read_gotchas",
        description=(
            "Read the NURL gotchas / pitfalls guide (`docs/GOTCHAS.md`) "
            "documenting common mistakes and surprising behaviour. "
            "Equivalent to the `nurl://gotchas` resource."
        ),
        input_schema=NO_ARGS_SCHEMA,
    ),
]

TOOL_SPECS = {tool.name: tool for tool in TOOLS}


RESOURCES: list[ResourceSpec] = [
    ResourceSpec(
        uri="nurl://grammar",
        name="NURL grammar (EBNF)",
        description="The authoritative EBNF grammar for the current NURL version.",
    ),
    ResourceSpec(
        uri="nurl://readme",
        name="NURL README",
        description="Project README covering design, usage and toolchain. Use this to get general information about NURL. This is BIG. Use only when needed.",
        mime_type="text/markdown",
    ),
    ResourceSpec(
        uri="nurl://roadmap",
        name="NURL ROADMAP",
        description="Project ROADMAP covering planned features and direction.",
        mime_type="text/markdown",
    ),
    ResourceSpec(
        uri="nurl://gotchas",
        name="NURL gotchas",
        description="Common pitfalls and surprising behaviour when writing NURL. Read this before debugging tricky compile or runtime errors.",
        mime_type="text/markdown",
    ),
    ResourceSpec(
        uri="nurl://stdlib/{path}",
        name="NURL stdlib module",
        description="Source of a stdlib .nu module, e.g. 'core/option.nu'.",
    ),
    ResourceSpec(
        uri="nurl://example/{name}",
        name="NURL example program",
        description="Source of a bundled example, e.g. 'calculator.nu'.",
    ),
    ResourceSpec(
        uri="nurl://test/{name}",
        name="NURL compiler test",
        description="Source of a bundled compiler test, e.g. 'generic_struct.nu'.",
    ),
]

RESOURCE_SPECS = {resource.uri: resource for resource in RESOURCES}


PROMPTS: list[PromptSpec] = [
    PromptSpec(
        name="nurl_coding_assistant",
        description=(
            "Prime the assistant with NURL's syntax and conventions before "
            "asking it to write or review NURL code."
        ),
        arguments=[],
    ),
]

PROMPT_SPECS = {prompt.name: prompt for prompt in PROMPTS}


def render_nurl_coding_assistant_prompt() -> str:
    example = ""
    path = Path(NURL_EXAMPLES_DIR) / "calculator.nu"
    if path.is_file():
        example = path.read_text("utf-8", errors="replace")
    return (
        "You are helping a developer write NURL code.\n\n"
        "Key syntax reminders:\n"
        "  - Function: `@ name → ret_ty { body }` (not `fn name() -> ret_ty`)\n"
        "  - Return:   `^ expr`\n"
        "  - Call:     `( fname arg1 arg2 )` (parenthesised prefix)\n"
        "  - String:   backticks: `` `hello` ``\n"
        "  - Types:    `i` (i64), `u` (u64), `f` (f64), `b` (bool), "
        "`s` (string), `v` (void), `* T` (pointer to T)\n"
        "  - Imports:  ``$ `stdlib/core/option.nu` ``\n"
        "  - FFI:      ``& `libc` @ puts * i8 → i``\n\n"
        "Before writing, fetch the `nurl://grammar` resource (or call the "
        "`nurl_read_grammar` tool) to confirm syntax. Always validate "
        "generated code by calling `nurl_build_native` and inspecting "
        "`nurlc_errors`; fix and retry.\n\n"
        "Reference example (calculator.nu):\n"
        "```\n" + example + "\n```"
    )
