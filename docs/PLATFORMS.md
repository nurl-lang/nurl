# Platforms

Two distinct axes: where compiled NURL programs **run** (codegen targets) and
where the **toolchain itself** builds and runs (host platforms).

## Codegen targets (where compiled programs run)

The compiler emits LLVM IR and delegates native codegen to `clang`, so any
target clang supports is reachable in principle. NURL's IR carries no target
triple, so a single `zig cc --target=` (or `clang --target=`) drives every
cross build. Only Linux x86_64 and Windows x86_64 are exercised by the local
build scripts; the rest are produced through the
[`nurlapi/`](../nurlapi/) container's cross-compile endpoints (see
[`PLAYGROUND.md`](PLAYGROUND.md)).

| Platform | Backend | Status |
|---|---|---|
| Linux x86_64 | LLVM | primary dev target — `build.sh` + tests |
| Windows x86_64 | LLVM | fully supported — `build.bat` runs the same bootstrap + snapshot suite as `build.sh` |
| macOS x86_64 | LLVM + zig cc | cross-compiled via `POST /build_macos`; Mach-O links only libSystem (no Apple SDK). Runs on Apple Silicon via Rosetta 2. canvas/audio/libcurl-HTTP not supported. |
| macOS ARM64 | LLVM + zig cc | cross-compiled via `POST /build_target` (`target=macos-arm64`) — native Apple Silicon Mach-O, links only libSystem. Unsigned, so clear the quarantine attribute before running. |
| WebAssembly | wasm32-wasi | via the `nurlapi/` container (WASI SDK 24.0); browser execution via `browser_wasi_shim`. The self-hosting compiler itself also builds to wasm — see [`PLAYGROUND.md`](PLAYGROUND.md). |
| Linux ARM64 / RISC-V64 | LLVM + zig cc | cross-compiled via `POST /build_target` — fully-static `musl` ELFs (`linux-arm64-musl`, `linux-riscv64-musl`) or dynamic glibc (`linux-arm64-gnu`). Milk-V Duo (RISC-V C906) validated on-device. |
| Android / iOS | LLVM cross | planned |
| Embedded (no_std) | LLVM | planned |
| JVM | JVM bytecode | future |
| .NET CLR | CIL | future |

Unsigned macOS binaries: clear the Gatekeeper quarantine attribute with
`xattr -d com.apple.quarantine <bin>` before running.

## Host platforms (where the toolchain runs)

The shipped `nurlc` / `nurlpkg` binaries link **libc only** (optional FFI
libraries are pulled in `--as-needed`, so a program that uses none stays
libc-only), and the `nurl.sh` wrapper is POSIX `sh` — no bash, no make, no
Python. The toolchain therefore runs unmodified on glibc, musl (Alpine), and
BSD libc.

| Host | Status |
|---|---|
| Linux x86_64 (glibc) | primary dev host — `build.sh` + full corpus + sanitizers, every push/PR |
| Windows x86_64 | `build.bat` runs the same bootstrap + snapshot suite |
| FreeBSD x86_64 | built + bootstrapped + corpus run on a real FreeBSD 14.2 VM in CI (`.github/workflows/ci.yml`) — a **hard gate**: a FreeBSD failure fails CI. The base system's clang/openssl/zlib cover those FFI tests; `build.sh` needs `bash`. |
| Alpine / musl | libc-only binaries run; exercised via the static-`musl` cross builds above |
| macOS | host build works with Homebrew LLVM on `PATH` (see [`BUILDING.md`](BUILDING.md)) |

The FreeBSD job exists because it once caught a real regression the Linux gate
could not — async fibers silently no-op'd on FreeBSD. CI detail:
[`BUILDING.md`](BUILDING.md#continuous-integration).
