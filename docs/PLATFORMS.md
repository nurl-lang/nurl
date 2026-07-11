# Platforms

Two distinct axes: where compiled NURL programs **run** (codegen targets) and
where the **toolchain itself** builds and runs (host platforms).

Support is stated in tiers, defined by what continuous integration actually
verifies — not by intent:

- **Tier 1 — CI-tested.** Built, bootstrapped, and the full test corpus runs
  on every change. A failure blocks merge.
- **Tier 2 — CI-built, untested.** A release artifact is produced and its
  bootstrap fixed point verified in CI, but the test corpus does not run on
  that platform.
- **Tier 3 — cross-compile target / best effort.** Code paths exist and are
  exercised ad hoc (playground endpoints, one-off device validation); nothing
  in CI gates them.

## Host platforms (where the toolchain runs)

| Host | Tier | What is verified | Install |
|---|---|---|---|
| Linux x86_64 (glibc ≥ 2.28) | **1** | `build.sh` bootstrap fixed point + full corpus + examples gate + ASan/UBSan/LSan + peak-RSS / symbol-collision / leak gates, every push and PR; release artifact smoke-tested | `install.sh` |
| FreeBSD x86_64 | **1** | build + bootstrap + full corpus on a FreeBSD 14.2 VM in CI (hard gate); the *release* artifact leg is best-effort (`continue-on-error`) | `install.sh` |
| Linux ARM64 (glibc) | **2** | release workflow builds natively on an ARM64 runner (`--no-tests`) and smoke-tests a hello-world; not in `ci.yml` | `install.sh` |
| Windows x86_64 | **2** | release workflow runs `build.bat --no-tests` — bootstrap fixed point only; the test corpus (`run_tests.ps1` against `outputs-windows/` goldens, needs PowerShell 7) runs locally, not in CI | `install.ps1` |
| macOS (x86_64 / ARM64) | **3** | expected to build from source with Homebrew LLVM; unverified — no CI job, no release artifact, and the installer rejects Darwin | build from source |
| Alpine / musl | **3** | build from source only. The shipped Linux archives are glibc-linked and do **not** load under musl | build from source |

The shipped `nurlc` / `nurlpkg` binaries link **libc only** (optional FFI
libraries are pulled in `--as-needed`, so a program that uses none stays
libc-only), and the `nurl.sh` wrapper is POSIX `sh` — no bash, no make, no
Python. Linux archives are relinked against a glibc 2.28 floor
(`tools/relink-toolchain-portable.sh`).

## Codegen targets (where compiled programs run)

The compiler emits LLVM IR and delegates native codegen to `clang`, so any
target clang supports is reachable in principle. NURL's IR carries no target
triple, so a single `zig cc --target=` (or `clang --target=`) drives every
cross build. Linux x86_64 and Windows x86_64 are exercised by the local build
scripts; the rest are produced through the [`nurlapi/`](../nurlapi/)
container's cross-compile endpoints (see [`PLAYGROUND.md`](PLAYGROUND.md)).

| Target | Backend | Tier | Notes |
|---|---|---|---|
| Linux x86_64 | LLVM | 1 | primary target — `build.sh` + full corpus |
| Windows x86_64 | LLVM (mingw-w64) | 2 | separate Windows goldens (`compiler/tests/outputs-windows/`); corpus runs locally via `build.bat`, not in CI |
| macOS x86_64 | LLVM + zig cc | 3 | `POST /build_macos`; Mach-O links only libSystem (no Apple SDK). Runs on Apple Silicon via Rosetta 2. canvas/audio/libcurl-HTTP not supported |
| macOS ARM64 | LLVM + zig cc | 3 | `POST /build_target` (`target=macos-arm64`) — native Apple Silicon Mach-O, links only libSystem. Unsigned: clear quarantine before running |
| WebAssembly | wasm32-wasi | 3 | via the `nurlapi/` container (WASI SDK 24.0); browser execution via `browser_wasi_shim`. The self-hosting compiler itself also builds to wasm — see [`PLAYGROUND.md`](PLAYGROUND.md) |
| Linux ARM64 / RISC-V64 | LLVM + zig cc | 3 | `POST /build_target` — fully-static `musl` ELFs (`linux-arm64-musl`, `linux-riscv64-musl`) or dynamic glibc (`linux-arm64-gnu`). Milk-V Duo (RISC-V C906) validated on-device (one-off, not CI) |
| Android / iOS | LLVM cross | — | planned |
| Embedded (no_std) | LLVM | — | planned |

Unsigned macOS binaries: clear the Gatekeeper quarantine attribute with
`xattr -d com.apple.quarantine <bin>` before running.

CI details: [`BUILDING.md`](BUILDING.md#continuous-integration).
