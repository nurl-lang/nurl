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
| Windows x86_64 | **1** | the `windows-tests` workflow runs `build.bat` — bootstrap fixed point + the full Windows golden corpus (`run_tests.ps1`) — on every push to `main` **and every PR**, so a Windows-only regression cannot reach `main`; the release job builds with `--no-tests` | `install.ps1` |
| macOS ARM64 (Apple Silicon) | **1** | the `macos-tests` workflow runs `./build.sh` — bootstrap fixed point + the full corpus, against the **same** `outputs/` goldens as Linux and FreeBSD — on every push to `main` **and every PR**, plus the `nurl.sh` driver end to end and the examples gate. Requires Homebrew LLVM: Xcode's clang cannot parse `nurlc`'s IR (see [`BUILDING.md`](BUILDING.md)). No release artifact yet — the installer still rejects Darwin, so the install route stays build-from-source | build from source |
| macOS x86_64 (Intel) | **3** | no CI. GitHub's last Intel image (`macos-13`) never left the queue across ten attempted runs, and a required check that cannot schedule blocks every PR — so the leg was removed rather than left permanently pending. The code paths are the ARM64 ones plus a different codegen backend; unverified | build from source |
| Alpine / musl | **3** | build from source only. The shipped Linux archives are glibc-linked and do **not** load under musl | build from source |

On **Windows**, building a program works with no Visual Studio and no
LLVM: the archive bundles a `zig cc`, and carries a MinGW-ABI runtime
object (`stdlib\runtime.mingw.o`) for it alongside the MSVC one that a
system clang uses — the two ABIs cannot share an object. Programs built
through the bundled zig cannot use the canvas or zstd FFI (both need MSVC
import libs); everything else, gzip included, is unaffected.

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
| Windows x86_64 | LLVM (mingw-w64) | 1 | separate Windows goldens (`compiler/tests/outputs-windows/`); corpus runs on every push and PR via the `windows-tests` workflow |
| macOS x86_64 | LLVM + zig cc | 3 | `POST /build_macos`; Mach-O links only libSystem (no Apple SDK). Runs on Apple Silicon via Rosetta 2. canvas/audio/libcurl-HTTP not supported |
| macOS ARM64 | LLVM + zig cc | 3 | `POST /build_target` (`target=macos-arm64`) — native Apple Silicon Mach-O, links only libSystem. Unsigned: clear quarantine before running |
| WebAssembly | wasm32-wasi | 3 | via the `nurlapi/` container (WASI SDK 24.0); browser execution via `browser_wasi_shim`. The self-hosting compiler itself also builds to wasm — see [`PLAYGROUND.md`](PLAYGROUND.md) |
| Linux ARM64 / RISC-V64 | LLVM + zig cc | 3 | `POST /build_target` — fully-static `musl` ELFs (`linux-arm64-musl`, `linux-riscv64-musl`) or dynamic glibc (`linux-arm64-gnu`). Milk-V Duo (RISC-V C906) validated on-device (one-off, not CI) |
| Unikernel x86_64 | LLVM + unikernel nolibc | 1 | the program **boots as its own kernel** — PVH ELF for QEMU microvm, and the same image boots under Firecracker and cloud-hypervisor. The guest gate (corpus subset against hosted goldens, device demos, faults, an HTTP server answering the host, a virtio-blk disk written across three boots and validated by `fsck.vfat` — not the full corpus) runs in CI on every change and blocks merge. `POST /build_unikernel` in the playground. See [`unikernel/README.md`](../unikernel/README.md) |
| Unikernel AArch64 / RISC-V64 | LLVM + zig cc + unikernel nolibc | 1 | QEMU `virt`; AArch64 also emits a flat `Image` for Firecracker / cloud-hypervisor (those need an ARM64 host). Per-arch QEMU gates (same scope as x86_64's) run in CI on every change and block merge. AArch64 via `POST /build_unikernel` `arch` |
| Android / iOS | LLVM cross | — | planned |
| Embedded (no_std) | LLVM | — | planned |

Unsigned macOS binaries: clear the Gatekeeper quarantine attribute with
`xattr -d com.apple.quarantine <bin>` before running.

CI details: [`BUILDING.md`](BUILDING.md#continuous-integration).
