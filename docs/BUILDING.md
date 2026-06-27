# Building NURL

The only build-time dependency is **clang / LLVM 15+**. No Python, no make,
no language-specific package manager. Clone the repo and run `./build.sh`
(or `build.bat` on Windows). The committed `compiler/nurlc_lastgood.ll`
snapshot is the only thing that boots the self-hosted chain.

Optional stdlib features pull in their own pkg-config libraries at link
time (`libpq-dev`, `libsqlite3-dev`, `libssl`, `libcurl`, `libz`, …); each
degrades with a clear diagnostic when absent. See
[`LIMITATIONS.md`](LIMITATIONS.md).

## Prerequisites

| Tool | Purpose |
|---|---|
| clang / LLVM 15+ | Compile LLVM IR (`.ll`) to a native binary; the only required build-time dependency |

**Windows** — install LLVM from [llvm.org/releases](https://llvm.org/releases/)
(the Windows installer adds `clang.exe` to `PATH`). Command Prompt,
PowerShell, or Git Bash all work.

**Linux (Debian/Ubuntu)** — `sudo apt install clang`

**Linux (Fedora/RHEL)** — `sudo dnf install clang`

**macOS** — `brew install llvm`, then add it to `PATH`:
```sh
export PATH="$(brew --prefix llvm)/bin:$PATH"   # add to ~/.zshrc to persist
```

**FreeBSD** — the base system already ships `clang`; `build.sh` needs `bash`
(`pkg install -y bash`), plus `pkgconf` + `sqlite3` for the SQLite FFI tests.
The toolchain binaries themselves link only libc, so they also run on
musl/Alpine without extra packages (see [`PLATFORMS.md`](PLATFORMS.md)).

## Step 1 — Build the C runtime (once)

```sh
clang -c stdlib/runtime.c -o stdlib/runtime.o      # Linux / macOS
clang -c stdlib\runtime.c -o stdlib\runtime.o      # Windows
```

> `stdlib/runtime.o` is already checked in; rebuild it only if you modify `runtime.c`.

## Step 2 — Bootstrap the self-hosting compiler

```sh
./build.sh        # Linux / macOS
build.bat         # Windows
```

The build script performs a complete bootstrap:

1. Links the committed `compiler/nurlc_lastgood.ll` snapshot →
   `build/nurlc_lastgood.bin` (stage 0 — the only step that doesn't already
   need a working `nurlc`).
2. `nurlc_lastgood.bin` compiles `compiler/nurlc.nu` → `build/nurlc_self` (stage 1).
3. `nurlc_self` compiles `compiler/nurlc.nu` again → `build/nurlc_self2` (stage 2).
4. Verifies stages 1 and 2 produce **byte-identical LLVM IR** (the bootstrap fixed point).
5. Copies stage 2 to `build/nurlc` and symlinks it at the repo root.
6. Runs the snapshot test suite (`compiler/tests/run_tests.sh` /
   `run_tests.bat`) and diffs against the golden baseline.

It prints `BUILD SUCCESS & TESTS PASSED` on success, or the full log / diff
on failure. All artefacts land under `build/`.

When a grammar / runtime-ABI change leaves the committed snapshot unable to
compile the current `nurlc.nu`, refresh it with `./build.sh
--refresh-bootstrap` (uses the existing `build/nurlc` to regenerate both
`compiler/nurlc_lastgood.nu` and `.ll`; commit both files together).

**Clean:** `./clean.sh` / `clean.bat`.

**Manual bootstrap (if needed):**
```sh
mkdir -p build
# Stage 0: link the committed snapshot IR → a working boot compiler.
clang compiler/nurlc_lastgood.ll stdlib/runtime.o -lm -lpthread -o build/nurlc_lastgood.bin
# Stage 1: boot compiler self-compiles → fresh self-hosted nurlc.
build/nurlc_lastgood.bin compiler/nurlc.nu > build/nurlc.ll
clang build/nurlc.ll stdlib/runtime.o -lm -lpthread -o build/nurlc
```

## Compile a `.nu` file

**Recommended (automated):**
```sh
./nurl.sh myprogram.nu              # → ./myprogram          (Linux/macOS)
./nurl.sh myprogram.nu myoutput     # → ./myoutput
nurl.bat  myprogram.nu              # → myprogram.exe         (Windows)
```

**Manual (two-step):**
```sh
./nurlc myprogram.nu > myprogram.ll               # or build/nurlc
clang myprogram.ll stdlib/runtime.o -o myprogram
./myprogram
```

## Debugging with `gdb` / `lldb` (DWARF)

NURL emits DWARF debug info, so a NURL binary drives under `gdb` / `lldb`
like any C-toolchain ELF: source-level breakpoints, single-step by `.nu`
line, `info locals`, `print x` with the NURL type name.

```sh
./nurl.sh --debug examples/fizzbuzz.nu          # builds fizzbuzz with DWARF
gdb -ex 'break fizzbuzz' -ex run ./fizzbuzz     # break by name
gdb -ex 'break examples/fizzbuzz.nu:18' …       # break by source line
```

Two knobs cooperate:
- `nurlc --g <file>` emits `!DICompileUnit` / `!DISubprogram` /
  `!DILocation` / `!DILocalVariable` metadata into the IR.
- `nurl.sh --debug` forwards `--g` AND links with `-g -rdynamic` against a
  freshly-built non-LTO `runtime_debug.o` (LTO silently drops DWARF in the
  current LLVM/gcc-ld pipeline, hence the side-by-side runtime build).

Runtime panics print a stack backtrace before aborting; pipe each frame's
`binary+0xOFFSET` through `addr2line -e <binary>` to recover `.nu:LINE`
locations. ASan / UBSan reports under `./build.sh --san` render `.nu`
locations directly. End-to-end regression: `./tools/dwarf_test.sh` (no-op
when `gdb` isn't installed).

## Bootstrap chain

Stage 0 links the committed `compiler/nurlc_lastgood.ll` snapshot —
pre-compiled IR of `compiler/nurlc_lastgood.nu`, a checked-in mirror of the
last self-host-stable `nurlc.nu`. Anyone with `clang` can clone and build;
no other-language toolchain is required.

- `compiler/nurlc_lastgood.nu` — NURL source of the snapshot (human-readable;
  identical to `nurlc.nu` at the point it was captured).
- `compiler/nurlc_lastgood.ll` — LLVM IR text, diffable in git and
  target-triple-agnostic, so the same blob bootstraps Linux / macOS / Windows.

Snapshot refresh: `./build.sh --refresh-bootstrap` (re-runs the existing
`build/nurlc` on the current `nurlc.nu` and overwrites both `.nu` and `.ll`;
commit them together).

## Continuous integration

Every push and pull request runs [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

| Job | What it checks |
|---|---|
| build + bootstrap fixed point + test corpus | `build.sh` on Linux x86_64 — stage1 ≡ stage2 byte-identical IR, then the snapshot test suite |
| examples corpus frontend gate | every program under `examples/` compiles (`tools/check_examples.sh`) |
| `nurlfmt --check` | the whole tree is in canonical format (no drift) |
| AddressSanitizer + UndefinedBehaviorSanitizer | `build.sh --san` + the corpus under ASan/UBSan/LSan |
| FreeBSD (VM) | full build + bootstrap + corpus on a real FreeBSD 14.2 guest (`vmactions/freebsd-vm`); the second OS that keeps libc/`sh`-portability honest — it once caught a regression Linux could not (async fibers silently no-op'd on FreeBSD). A hard gate: a FreeBSD failure fails CI. |

A local `./build.sh` reproduces the first two gates; `./build.sh --san` then
`./compiler/tests/run_san_tests.sh` reproduces the sanitizer gate; and
`./compiler/tests/nurlfmt_check.sh` reproduces the format gate.
