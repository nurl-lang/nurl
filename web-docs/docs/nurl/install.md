---
outline: deep
title: Installation
order: 2
---

# Installation

NURL can be obtained in two ways: installing a prebuilt toolchain or by building them from the source code.

## Prebuilt toolchain (Linux / FreeBSD / Windows)

> -- description tbd --

This gives you `nurlc` (compiler), `nurlpkg` (package manager), and
`nurlfmt` (source formatter) on your `PATH`.

### One command install 

Linux / FreeBSD
```bash
curl -fsSL https://nurl-lang.org/install.sh | sh
```

Windows (PowerShell)
```ps
irm https://nurl-lang.org/install.ps1 | iex
```
::: details Why is there no prebuilt path for macOS?
NURL's CI currently builds and tests on **Linux and FreeBSD** only. macOS
support exists, but there's no CI coverage or prebuilt toolchain for *running on*
macOS yet — hence "build from source" being the macOS path for now.
:::

### TBD other ways

## Option B — Build from source

Needed for macOS, and generally recommended if you want to compile your
own `.nu` files right away.

### Prerequisites

NURL's compiler emits LLVM IR text; `clang` turns that into a native binary.
It's the **only** required build-time dependency.

| OS | Command |
|---|---|
| Linux | Use distribution's package manager |
| macOS | `brew install llvm` (then add it to `PATH` — see below) |
| Windows | Install from [llvm.org/releases](https://llvm.org/releases/) |
| FreeBSD | already ships `clang`; also install `bash` for `build.sh` |

macOS's brew-installed LLVM isn't symlinked onto `PATH` by default. Add this line to `~/.zshrc` to persist it
```bash
export PATH="$(brew --prefix llvm)/bin:$PATH"
```

### Clone and build

```bash
git clone https://github.com/nurl-lang/nurl.git
cd nurl
./build.sh          # Linux / macOS / FreeBSD
build.bat           # Windows
```

`./build.sh` performs a full **bootstrap**: it compiles the C runtime,
links a committed known-good compiler snapshot, uses that to compile the
current compiler source, compiles it *again* with the result, and checks
that both self-compiles produce byte-for-byte identical output before
accepting the build. On success it prints `BUILD SUCCESS & TESTS PASSED`
and leaves the compiler at `build/nurlc` (symlinked at the repo root).

::: details Why compile the compiler with itself, twice?
The compiler (`compiler/nurlc.nu`) is written in NURL. To prove a change to
the compiler didn't silently break itself, `build.sh` compiles the compiler
source with itself, then does it *again* using the result of the first
pass, and requires the two outputs to be byte-identical. This "fixed point"
check is the same idea GCC and Zig use to validate a self-hosting compiler.
:::

### Optional: language server + editor extension

```bash
./install.sh
```

Run from the repo root after `./build.sh` — it
bootstraps the compiler if needed, builds `nurl-lsp`, symlinks it onto your
`PATH`, and installs the VS Code extension if `code` (or `cursor` /
`windsurf`) is available. Safe to re-run any time. See
`docs/TOOLING.md` for manual editor setup and other editors.

## Verifying the install

```bash
./build/nurlc --version      # after a source build
nurlc --version              # after the prebuilt installer
```