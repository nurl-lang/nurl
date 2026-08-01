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

**macOS** — `brew install llvm`, then add it to `PATH`. Note: macOS host
builds are not covered by CI (see [`PLATFORMS.md`](PLATFORMS.md)):
```sh
export PATH="$(brew --prefix llvm)/bin:$PATH"   # add to ~/.zshrc to persist
```

**FreeBSD** — the base system already ships `clang`; `build.sh` needs `bash`
(`pkg install -y bash`), plus `pkgconf` + `sqlite3` for the SQLite FFI tests.
The toolchain binaries themselves link only libc, so they also run on
musl/Alpine without extra packages (see [`PLATFORMS.md`](PLATFORMS.md)).

## Step 1 — Build the C runtime

`./build.sh` (Step 2) compiles the C runtime for you, so most contributors
can skip straight to Step 2. Build it by hand only for the manual bootstrap
below:

```sh
clang -c stdlib/runtime.c -o stdlib/runtime.o      # Linux / macOS
clang -c stdlib\runtime.c -o stdlib\runtime.o      # Windows
```

> `stdlib/runtime.o` is **not** checked in (it is gitignored). `./build.sh`
> regenerates it; note that the build compiles it with `-flto`, so after a
> build `runtime.o` is LLVM bitcode and the build also emits a plain-ELF
> `stdlib/runtime.native.o` for non-LTO linking (see below).

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
6. Runs the snapshot test suite (`compiler/tests/run_tests.sh`; on
   Windows `run_tests.ps1`, which needs PowerShell 7) and diffs against
   the golden baseline.

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
./nurlc myprogram.nu > myprogram.ll                          # or build/nurlc
clang myprogram.ll stdlib/runtime.native.o -lm -lpthread -o myprogram
./myprogram
```

> Link against `stdlib/runtime.native.o` (a real ELF object), not
> `stdlib/runtime.o` — after `./build.sh` the latter is LLVM bitcode and a
> plain `clang` link rejects it with *"file format not recognized"*. The
> `-lm -lpthread` libraries are required.

## What ends up in the `.ll`

`nurlc` emits only the functions `main` can reach. An import brings in a
whole module — a program that imports `stdlib/ext/json.nu` for
`json_parse` also parses `json_clone`, the pretty-printer and the float
formatter — and emitting all of it means clang runs its `-O2` pipeline
over code LTO then deletes at link time. Dropping it at the source of
the IR instead is worth 30–40% of the clang step on a stdlib-heavy
program (`examples/static_server.nu`: 1,416 emitted functions down to
469, 6.6 s of clang down to 3.8 s). The final binary is unchanged —
LTO was already removing the same code, just later.

The pass runs over the finished IR text, so it needs no special
knowledge of closures, generic monomorphisations, drop glue or dyn
vtables: a function is live when something emitted names it. Roots are
`main` plus anything named at module scope (a `@__vt.…` vtable constant
holds its method thunks there). A file with **no `main`** is a module
compiled for something else to link against, so the pass leaves it
whole.

Two things make it safe to have on by default: the output is a
sub-sequence of the unfiltered IR — nothing is rewritten, reordered or
renamed — and dropping something still referenced is an undefined
symbol at link time, never a wrong binary.

`nurlc --no-dce <file>` emits everything, which is what you want when
diffing IR against an older compiler or linking a NURL object into a C
program by hand.

## Parallel lowering (`--split`)

Even after dead-function elimination, the clang step is what a NURL
build waits on, and it is *one* single-threaded LLVM `-O2` pipeline over
*one* module. Lowering the compiler's own 3.2 MB of IR takes 11.3 s
while emitting it takes 0.46 s, and idle cores stay idle: `-flto` with
`-plugin-opt=jobs=12` parallelises only the codegen tail and still
measures 11.1 s.

So `nurl.sh` asks `nurlc` for the module *as several independent
modules*, lowers them at once, and links them with ThinLTO — which
carries cross-module inlining through its bitcode summaries and runs its
own backend in parallel. On twelve cores, the compiler's clang step:

| | one module, `-flto` | 12 parts, `-flto=thin` |
|---|---:|---:|
| clang step | 11.3 s | **2.0 s** |

The whole module still reaches stdout, so `myprogram.ll` is byte for
byte what it always was; the parts are written beside it and removed
after the link.

**The trade.** ThinLTO imports across a module boundary, but not
unconditionally, so a caller separated from a callee it wanted inlined
stays separated. The split-built compiler retires **3.4% more
instructions** than the single-module one (3.242e9 vs 3.135e9 under
`perf stat`, self-compile). A 5.6× cheaper build for 3.4% of the
program's speed — worth it while you iterate, not worth it for what you
ship. The drivers follow that rule rather than a global default:

- **`nurl.sh` splits your program**, because you rebuild it constantly.
- **`build.sh` splits the throwaway stage-1 compiler**, but links the
  stage-2 one it installs as `build/nurlc` as a single module.

The bootstrap applies the same rule to the optimisation level, not just
the partition — see [Only stage 2 is optimised](#only-stage-2-is-optimised).

Controls:

| | |
|---|---|
| `NURL_SPLIT=0` | never split — the old behaviour exactly. Use it for a release build. |
| `NURL_SPLIT=N` | at most `N` parts (default: one per core, capped at 16). |
| `NURL_SPLIT_MIN=BYTES` | smallest a part may be (default 131072). |

`N` is a *ceiling*: `nurlc` splits only as far as it can keep every part
above the floor, so a program under ~256 KB of IR is never split at all.
That floor is not about build time — cutting a small module up makes it
*slower*. `bench/sort_window.nu` (10 KB of IR) runs 20–42% slower split
at any part count, and `bench/hash_join.nu` (27 KB) 23% slower at twelve,
while the compiler's 3.2 MB is unaffected at every count tried.

Splitting is off for `--emit-ir`, `--emit-asm`, `-O0`, `NURL_SAN=1`, and
`--debug` / `--coverage` — `nurlc` refuses `--split` together with `--g`,
because DWARF is a per-module metadata graph that a function's `!dbg`
attachments point into, and partitioning would strand them.

The partition itself is a text-level pass over the finished IR, on the
same footing as dead-function elimination above: a function goes to one
part, everything a part does not define it declares, `private` globals
follow the functions that name them, module-level globals are defined in
part 0 and declared `external` in the rest. A reference that lands in
the wrong part is an unparseable module or an undefined symbol — loud,
never a silently wrong binary — and `compiler/tests/split_equivalence.sh`
rebuilds a structurally varied corpus both ways on every `./build.sh` to
prove the programs match.

Windows (`nurl.bat`) links a single module and is unaffected.

## Debugging with `gdb` / `lldb` (DWARF)

NURL emits DWARF debug info, so a NURL binary drives under `gdb` / `lldb`
like any C-toolchain ELF: source-level breakpoints, single-step by `.nu`
line, `info locals`, `print x` with the NURL type name.

```sh
./nurl.sh -O0 --debug examples/fizzbuzz.nu            # DWARF, no optimisation
gdb -ex 'break fizzbuzz' -ex run ./examples/fizzbuzz  # break by name
gdb -ex 'break examples/fizzbuzz.nu:18' …             # break by source line
```

Pass `-O0` (or `-O1`): at the default `-O2`, optimisation inlines and
reorders enough that source-line breakpoints and `info locals` become
unreliable — the breakpoint may never fire. `nurl.sh` writes the binary
next to the source, so a program under `examples/` lands at
`./examples/fizzbuzz`, not `./fizzbuzz`.

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

### Only stage 2 is optimised

Stages 0 and 1 are scaffolding. Neither binary is shipped or benchmarked,
and each one does exactly one job — compile `nurlc.nu` once — before the
build deletes it. `build.sh` therefore links them `-O0` and keeps `-O2`
for stage 2, the one copied to `build/nurlc`.

The trade is the same one the split above makes, pushed further: a
throwaway compiler is allowed to be slow, because what it costs to *make*
it fast dwarfs what the speed gives back. Stage 0 is the extreme case —
it links the committed snapshot, which is one file by definition, so it
is the one link the split cannot help.

| step | `-O2` | `-O0` |
|---|---:|---:|
| stage 0 link | 12.89 s | **0.75 s** |
| stage 1 link (split) | 1.93 s | **0.30 s** |
| stage 1 ir (emit) | 0.38 s | 0.88 s |
| stage 2 ir (emit) | 0.35 s | 0.78 s |
| stage 2 link | 12.54 s | 12.49 s |
| **`build.sh --no-tests`, end to end** | **36.3 s** | **23.6 s** |

Twelve cores, clang 18. The two stages get ~2× slower at the one thing
they do and the build still comes out 35% shorter.

**This cannot change what gets built.** The IR a stage emits is
byte-identical at either level — the bootstrap fixed point (stage 1 ≡
stage 2, byte for byte) is checked on every build and would fail loudly
otherwise, and stage 2's own link flags are untouched, so `build/nurlc`
is the same binary it always was.

Sanitized builds (`--san`) stay `-O2` throughout: LTO is already off
there, so the link is not the expensive part, and the instrumented
self-compile is the stage that runs closest to CI's memory and time
limits — `-O0` would slow down the thing that is already slowest.

## Continuous integration

Every pull request, and every push to `main`, runs
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

| Job / step | What it checks |
|---|---|
| build + bootstrap fixed point + test corpus | `build.sh` on Linux x86_64 — stage1 ≡ stage2 byte-identical IR, then the snapshot test suite |
| self-compile peak-RSS gate | `tools/memgate.sh` — compiling the compiler must stay under the memory budget |
| self-compile leak gate | `tools/leakgate.sh` — `nurlc compiler/nurlc.nu` must leak nothing under LSan; runs when `compiler/nurlc.nu` changes |
| examples corpus frontend gate | every program under `examples/` compiles (`tools/check_examples.sh`) |
| stdlib symbol-collision gate | no two stdlib helpers mangle to the same symbol (`tools/check_stdlib_symbols.sh`) |
| `nurlfmt --check` | the whole tree is in canonical format (no drift) |
| HTTP per-request leak gate | `tools/leakcheck/run.sh` — the HTTP server serves a request burst leak-free under LSan |
| AddressSanitizer + UndefinedBehaviorSanitizer | `build.sh --san` + the corpus under ASan/UBSan, plus a leak-pinned test set under LSan |
| FreeBSD (VM) | full build + bootstrap + corpus on a real FreeBSD 14.2 guest (`vmactions/freebsd-vm`) — a hard gate that keeps libc/`sh` portability honest |

A local `./build.sh` reproduces the first two gates; `./build.sh --san` then
`./compiler/tests/run_san_tests.sh` reproduces the sanitizer gate; and
`./compiler/tests/nurlfmt_check.sh` reproduces the format gate.
