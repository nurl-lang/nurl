# Target platforms

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
