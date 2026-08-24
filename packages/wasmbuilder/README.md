# wasmbuilder

Compile NURL to **wasm32-wasi locally** — no wasi-sdk, no Docker, no build
service. One install command brings everything:

```sh
curl -fsSL https://nurl-lang.org/install.sh | sh
export PATH="$HOME/.nurl/bin:$PATH"
nurlpkg install wasmbuilder

wasmbuilder program.nu            # → program.wasm
```

Run the result with any wasm runtime — the external `wasmtime`, or the
pure-NURL one from this registry:

```sh
nurlpkg install nwasm
nwasm run program.wasm
```

## How it works

The installed toolchain already contains everything a wasm build needs;
wasmbuilder just drives it:

1. **`nurlc`** compiles your program to LLVM IR (host-targeted).
2. The **IR rewriter** retargets that IR for `wasm32-unknown-wasi`. This is
   the production pipeline extracted from the play.nurl-lang.org build
   service: `@main` is renamed to the wasi crt entry, libc calls whose NURL
   FFI uses 64-bit widths where wasm32's libc expects 32 get trunc/zext
   shim wrappers, POSIX-only symbols wasi-libc doesn't ship (mmap, fork,
   pthread…) become error-sentinel stubs behind the stdlib's runtime
   gates, and every remaining external symbol is annotated as a potential
   `env` wasm import — so canvas/audio/GPU host imports resolve at run
   time instead of failing the link.
3. The toolchain's **bundled `zig cc`** (which `nurl.sh` already prefers
   for native builds) compiles + links the module: zig carries its own
   wasi-libc and wasm-ld, which is what makes wasi-sdk unnecessary.
4. The **NURL runtime** (`runtime.wasm.o`) is compiled from the installed
   stdlib's `runtime.c` on first use and cached under
   `$NURL_HOME/build/wasmbuilder/`, keyed by the source's content hash —
   upgrading the toolchain automatically rebuilds a matching runtime.

If no zig is found at all (for example a Windows install, or a Linux
toolchain installed with the clang fallback), wasmbuilder downloads the
pinned zig 0.16.0 release **once**, sha256-verified against
ziglang.org's release index, into `$NURL_HOME/zig` — after which builds
are fully offline. Set `NURL_WASM_NO_DOWNLOAD=1` to forbid the download
and fail instead.

## CLI

```
wasmbuilder <file.nu> [options]

  -o, --output FILE        output path (default: <input>.wasm)
  -O, --opt LEVEL          0..3 or z (default 2; z = size)
      --emit-ll            keep the rewritten wasm32 .ll next to the output
      --asyncify           wasm-opt asyncify wrap for canvas programs
                           (needs binaryen's wasm-opt on PATH)
      --asyncify-imports L comma-separated async import names
                           (e.g. env.wgpu_download); implies --asyncify
      --obj FILE           extra wasm object(s) linked in, space-separated
                           (e.g. a kernels_static.wasm.o, so `& c` symbols
                           resolve statically instead of becoming imports)
      --cflags FLAGS       extra compile/link flags, space-separated
                           (e.g. "-msimd128" for wasm SIMD)
      --no-gc-sections     keep unreachable code at link time — see below
      --no-host-imports    don't pass --ffi-host-imports to nurlc
  -q, --quiet              suppress progress output
      --doctor             show how nurlc / zig / runtime resolve here
      --version, -h
```

`--doctor` is the first thing to run when something is off — it prints
each resolution step (nurlc, stdlib C sources, wasm compiler, cache dir)
and what would happen next.

### `--gc-sections` is the default (and `--no-gc-sections` the escape hatch)

Since 0.1.4 modules are linked with `-Wl,--gc-sections`: unreachable
code — mostly the part of the NURL runtime a program never calls — is
dropped at link time. It is worth ~25 % of the module (`bench/lcg.nu`:
1064 KiB → 820 KiB) and most of a JIT runtime's load-the-module floor
(an empty program under the external `wasmtime`: ~60 ms → ~10 ms),
because the runtime stops translating code nothing reaches.

Earlier versions defaulted to `--no-gc-sections`, citing a real trap:
NURL closures store function-table indices, section GC renumbers that
table, and `nurlc.wasm` (>150 functions) was observed to `call_indirect`
-trap under it. That blocker was re-tested at exactly the documented
scale on 2026-07-27 and does not reproduce: a `--gc-sections`-linked
`nurlc.wasm` **self-compiles the 65k-line compiler byte-identically to
the native binary** under both the external `wasmtime` and the
pure-NURL `nwasm`, and the closure corpus (`test_05_closures_and_capture`,
`test_06_torture_chamber`) passes. Today's `wasm-ld` relocates
address-taken functions correctly through GC.

`--no-gc-sections` (library: `WbOpts.no_gc_sections`) restores the old
behaviour. If a program ever traps on an indirect call *only* under the
default, that is a table-renumbering bug resurfacing: switch it off and
please report it. Use the flag rather than
`--cflags "-Wl,--no-gc-sections"` — the latter appends after the flag
this builder already passes and leaves the outcome to wasm-ld's
last-one-wins ordering.

## Library use (embed the builder)

Other packages depend on wasmbuilder to compile wasm **in-process** — no
subprocess orchestration, no HTTP build API. This is how swarm-mcp
compiles compute kernels and how nurl-mcp exposes a local build-wasm tool:

```nurl
$ `deps/wasmbuilder/src/build.nu`

: ~ WbOpts opts ( wb_opts_default )
= . opts quiet T
: !( Vec u ) String r ( wb_build_source kernel_src `kernel.nu` opts )
?? r {
    T wasm_bytes → { … ship to workers … }
    F err → { … structured error, nurlc diagnostics included … }
}
```

`wb_build_file nu_path out_wasm opts → !v String` is the file-to-file
variant the CLI wraps; it also handles multi-file programs (imports
resolve exactly as a native `nurl` build would).

## Environment

| Variable                | Effect                                            |
|-------------------------|---------------------------------------------------|
| `NURL_HOME`             | toolchain prefix (default `~/.nurl`)              |
| `NURLC`                 | explicit nurlc binary                             |
| `NURL_ZIG`              | explicit zig binary (skips discovery)             |
| `WASI_CLANG`            | use a wasi-sdk clang instead of zig               |
| `NURL_WASM_NO_DOWNLOAD` | never download zig; fail with instructions        |
| `NURL_WASM_OPT`         | wasm-opt binary for `--asyncify` (default PATH)   |

## Limitations

* Programs using native-only libraries (e.g. `stdlib/ext/postgres.nu`)
  can't target wasm — the link reports the missing symbols.
* Threads don't exist on wasm32-wasi: `thread_spawn` fails gracefully at
  run time (pthread stubs return error), mirroring the playground.

## Tests

```sh
./tests/build_test.sh
```

Builds the CLI, compiles a corpus of repo examples to wasm, runs each
next to its native twin and diffs the output byte-for-byte, then
exercises the library API. The pipeline is also validated at scale: the
NURL compiler itself (65k lines) built through wasmbuilder produces
byte-identical output to its native twin under both the reference
wasmtime and the pure-NURL `nwasm`.
