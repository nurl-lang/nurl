# PLAYGROUND 2.0 — Static / WASM-First Playground Options

Status: design exploration (2026-05-27). No code changes; this document
enumerates the realistic paths from the current container-backed
playground at `play.nurl-lang.org` toward a deployment where the
**front-end is fully static** and the **build pipeline runs as WebAssembly**
(either entirely in-browser or in a tiny serverless shim) — with no
Docker container in the hot path.

The goal is to capture the engineering surface honestly: what is
already possible, what needs glue, and what is a research project. The
final section gives a recommended phased rollout.

---

## 1. What the current container actually does

`nurlapi/Dockerfile` produces a ~debian-bookworm image that bundles:

| Layer | Size order | Purpose |
|------|------------|---------|
| `clang-16` + LLVM | hundreds of MB | native ELF link |
| **WASI SDK 24** (`/opt/wasi-sdk`) | ~300 MB | `wasm32-wasi` clang + sysroot + `wasm-ld` |
| **Zig 0.13** (`/opt/zig`) | ~150 MB | macOS/RISC-V/ARM/musl cross-compile |
| **mingw-w64** + static `libcurl` | ~50 MB | Windows `.exe` + Schannel TLS |
| `libcurl/libssl/libsqlite3/libpq/libzstd/zlib` | small | native FFI |
| pre-built per-target `runtime.<id>.o` | small | one cold-link warmup per target |
| `nurlapi` itself (3 700 LOC `main.nu`) | ~500 KB | HTTP server + MCP + OAuth + playground UI |

`cloudflare/` wraps this image as a single-port Durable Object
(`NurlContainer`, port 8000) with `max_instances: 3`,
`instance_type: standard-1`, `sleepAfter: 10m`. Every request to
`play.nurl-lang.org` flows through the Worker → Container.

### 1.1 Endpoint inventory

From `nurlapi/main.nu:3641-3691` the live route table is:

- **Compile**: `POST /build`, `/build_wasm`, `/build_windows`,
  `/build_macos`, `/build_target`
- **Artifact**: `GET /download/:build_id/:filename`
- **Docs / corpus**: `/readme`, `/roadmap`, `/gotchas`, `/grammar`,
  `/stdlib`, `/tests`, `/license`, `/openapi.json`, `/examples`
- **Browser playground UI**: `/`, `/static/*`, `/favicon.{ico,svg}`
- **MCP**: `POST /mcp`, `GET /mcp`, `DELETE /mcp`, `/mcp-info`,
  `/.well-known/oauth-*`, `/register`, `/authorize`, `/token`
- **Health**: `/health`, `/targets`

For a *playground* (not the MCP server) we really only care about the
**Compile** + **UI** + **Docs** subsets. MCP/OAuth are orthogonal and
can keep living on the container.

### 1.2 Work the server actually performs for `/build_wasm`

`h_build_wasm` (main.nu:597) is the canonical hot path. It does:

1. Spawn `nurlc <src>` → captures LLVM IR text from stdout.
2. Run `prepare_ir_for_wasi` (NURL string-rewriting at main.nu:110-271)
   to (a) rename `@main` → `@__main_argc_argv`, (b) prepend wasm32
   triple+datalayout, (c) generate `__nurl_<libc>_shim` wrappers that
   bridge nurlc's `i64`-everywhere ABI to wasi-libc's `i32`/`size_t`
   prototypes.
3. Spawn `wasi-clang --target=wasm32-wasi -O2 <ir>
   runtime.wasm.o [canvas.wasm.o] [audio.wasm.o] -o <out>.wasm -lm`
   — this is the LLVM IR-to-wasm codegen **and** `wasm-ld` link
   against wasi-libc.
4. Base64-encode the resulting `.wasm` and ship it back to the browser.

Step 4 is then handed to `@bjorn3/browser_wasi_shim` and executed
in-page (static/index.html:728 onward). **The "run" half of the
playground is already fully client-side.** Only the "build" half
needs the container.

The other build endpoints (`/build`, `/build_windows`, `/build_macos`,
`/build_target`) are structurally identical but call `clang` /
`x86_64-w64-mingw32-gcc` / `zig cc` instead of `wasi-clang`.

### 1.3 What we already know works as WebAssembly

`buildwasm.sh` POSTs `compiler/nurlc.nu` to the live container's
`/build_wasm` and writes the output as `nurlc.wasm`. `wasmnurl.sh`
then runs `nurlc.wasm` under `wasmtime` to compile arbitrary `.nu`
sources to LLVM IR. **The compiler self-hosts to wasm32-wasi.** That
is the load-bearing fact of this document: anywhere wasmtime can run,
including the browser through `browser_wasi_shim`, the NURL compiler
runs.

The runtime shipped per-target (`runtime.wasm.o`, `canvas.wasm.o`,
`audio.wasm.o`) is also already wasm-native — they are the
`-c stdlib/runtime.c` outputs that `wasi-clang` links into the user's
program.

---

## 2. What does "static playground" mean — exact definition

Three increasingly strict definitions. We will refer back to these.

**S1 — "Static front-end."** HTML/JS/Monaco/docs are served from a
CDN (Cloudflare Pages, GitHub Pages, S3). The build endpoint is still
a server, but it can be a serverless function instead of a Durable
Object Container.

**S2 — "Static + WASM build."** The build step runs as WebAssembly.
It can run either in-browser **or** inside a Cloudflare Worker / Fastly
Compute / Deno Deploy isolate. No Docker, no Linux VM.

**S3 — "Truly static, no compute at all."** Everything runs in the
user's browser; the origin serves only flat files. The playground
works offline once cached.

Cross-target compilation (Linux x86_64, Windows, macOS, RISC-V,
ARM64) is **out of scope for S3** for the foreseeable future and
out of scope for S2 unless we ship a wasm-built `clang`+`lld` per
target (see §3.3). For S3 the playground reasonably supports
"wasm target only", same as the live `Run` button does today.

---

## 3. Options

### 3.1 Option A — Static front-end + serverless build Worker (S1+S2)

Ship the HTML/Monaco/examples to Cloudflare Pages. Replace the
Durable Object Container with a Cloudflare **Worker** that internally
hosts `nurlc.wasm`. The Worker accepts the same `/build_wasm` JSON
shape, runs `nurlc.wasm` under a thin WASI shim, performs the IR
rewrite, then calls the wasm linker (see §3.5) to produce the final
`.wasm`. Response identical to today.

**Pros**:
- No container cold-start (workers start in ms, not seconds).
- Tiny per-request memory and cost; auto-scales to zero.
- The wasm playground works for hello-world without any container
  spinning up.
- Cross-compile (Linux/Win/Mac/RISC-V) buttons keep pointing at the
  existing container — the user only pays for it when they actually
  click those buttons.

**Cons**:
- Workers have CPU-time limits (50 ms free / 30 s paid). A cold
  `nurlc.wasm` compile of a small program is well under that, but
  the *linker* (`wasm-ld` reimplemented in JS or compiled to wasm
  in the worker) may push the budget. Needs measurement.
- Worker size cap (~25 MB compressed). `nurlc.wasm` + `runtime.wasm.o`
  + a wasm linker has to fit, or be split across multiple workers.

**Effort**: medium — mostly orchestration, no new compiler work.

### 3.2 Option B — In-browser wasm build, lazy-loaded toolchain (S3)

The browser fetches `nurlc.wasm` + `runtime.wasm.o` (+ optionally
`canvas.wasm.o`, `audio.wasm.o`) on first build click. It runs
`nurlc.wasm` under `browser_wasi_shim` to get LLVM IR, runs the IR
rewriter (see §3.4), then runs a wasm-resident linker to produce
the final module. Build artifacts are cached in IndexedDB.

**Pros**:
- Once cached, the playground is **fully offline**.
- Zero per-request cost — no backend.
- The container can be retired entirely (S3 strict) or kept only
  for cross-compile targets (recommended hybrid).
- Privacy: the user's source never leaves their browser.

**Cons**:
- First-build penalty: the toolchain bundle (`nurlc.wasm` +
  `runtime.wasm.o` + linker) is conservatively 5-15 MB gzipped.
  Acceptable; Lichess/Stockfish, Rust Playground (rustc), and
  TypeScript Playground have set the precedent that a one-time
  5-20 MB toolchain download is normal.
- The IR rewriter currently lives in NURL inside `nurlapi/main.nu`.
  It must either be (a) re-implemented in JS, or (b) folded into
  `nurlc` as a `--target=wasm32-wasi` flag, or (c) compiled as its
  own `prepare_ir.wasm` shimmed alongside `nurlc.wasm`. **(b) is
  the right answer** — see §3.4.
- The linker is the hard part — see §3.3 and §3.5.

**Effort**: medium-high. The blocker is §3.3 / §3.5.

### 3.3 The linker problem (the only real obstacle)

Today the server runs `wasi-clang ... -o foo.wasm`, which internally
calls `wasm-ld`. To replicate this in a browser (B) or Worker (A) we
need an IR-to-wasm path *without* a 300 MB WASI SDK.

Four practical sub-options ordered from cheap to ambitious:

**3.3.a — Ship clang+lld compiled to wasm.** Real, working
implementations exist (Compiler Explorer's `clangd-in-browser`,
`bytecodealliance/wasmtime` ecosystem demos, `wasm-clang` projects
on GitHub). Bundle size: 30-80 MB compressed, 100-200 MB on disk.
Heavy but proven. IndexedDB cache amortizes cost.

**3.3.b — Skip LLVM, write a wasm backend in nurlc.** Add a new
codegen path `nurlc --emit=wasm` that emits WebAssembly bytecode
directly from nurlc's typed IR, bypassing LLVM entirely. The output
would need linking against a precompiled `runtime.wasm.o` (already
available) via a tiny resolver. NURL's typed IR is simpler than
LLVM's; this is plausible but a multi-month effort and gives up
LLVM's optimizer.

**3.3.c — Hybrid: nurlc emits raw wasm for "ready-to-link" object
files, then use a small JS linker.** Compromise between 3.3.a and
3.3.b: nurlc still goes through LLVM IR text for human-readable
diagnostics, but a separate `nurl-link.wasm` (Rust + `wasm-tools`
or `walrus`, compiled to wasm32-wasi, ~1-3 MB) does the linking.
Eliminates the 30-80 MB clang.wasm dependency. The IR-to-wasm step
*still* needs codegen — which means we're back to writing it (3.3.b)
or shipping `llc.wasm` (smaller than `clang.wasm`, maybe 15-30 MB).

**3.3.d — Pre-link the runtime into nurlc.wasm.** Build a fat
`nurlc.wasm` that already contains the runtime object inlined, and
have nurlc emit a self-contained wasm module that the browser can
instantiate directly. This works only if nurlc gains the codegen
from 3.3.b — there is no way around emitting wasm bytecode somewhere.

For S3 today, **3.3.a** is the only path that does not require new
compiler work. For long-term, **3.3.b** is the cleanest answer
because it removes LLVM as a dependency of the playground.

### 3.4 The IR-rewriter problem

`prepare_ir_for_wasi` (main.nu:110-271) does ~160 lines of
string-rewriting on the LLVM IR text. It is purely a function of
the IR plus a static libc shim table. Three options to host it:

1. **In-place (today).** Leave it in `nurlapi/main.nu`; the wasm
   playground keeps using the container. Doesn't help static
   deployment.
2. **Port to JS.** Translate the 160 lines to TypeScript. Cheap and
   keeps the rewriter out of nurlc itself, but means a second source
   of truth that has to track nurlc's calling conventions.
3. **Fold into nurlc.** Add `nurlc --target=wasm32-wasi`. nurlc itself
   already knows what libc it's about to call (it generated the
   `declare` lines), so doing the rewrite at emit time is strictly
   simpler than scanning the text afterwards. After this, the static
   playground (B/F/G) just calls `nurlc.wasm <src>` and gets ready-
   for-`wasm-ld` IR. **Recommended.**

Folding into nurlc is also the right move for `wasmnurl.sh` and any
future "nurlc as a standalone CLI emits wasm" use case — the
rewriter would no longer be locked to the nurlapi container.

### 3.5 What "linker" actually means in this context

`wasm-ld` resolves symbols, lays out the wasm module, and handles
relocations. For the playground's narrow case — link one user object
with one or two precompiled runtime objects (`runtime.wasm.o`,
optionally `canvas.wasm.o`, `audio.wasm.o`) targeting `wasi_snapshot_
preview1` — a *minimal* linker is much smaller than `lld`.

Candidates:

- `wasm-tools merge` (Bytecode Alliance, Rust, ~1 MB wasm).
- `walrus` (Rust crate, ~500 KB wasm) — programmatic wasm module
  manipulation; you write the linking logic in <500 lines.
- A pure-NURL linker (`stdlib/ext/wasm_link.nu`?) — feasible because
  the wasm binary format is well-specified and small. **Cleanest fit
  for the NURL self-hosting story** but a real engineering project
  (~weeks).
- Just use `clang.wasm` from §3.3.a. Big but works today.

The minimal linker has to handle: object file (relocations) parsing,
symbol resolution between user IR and runtime.wasm.o, function/table
index renumbering, data section concatenation, export merging,
imports unification. It is bounded work.

---

## 4. Cross-compile targets — what about Linux/Win/Mac/RISC-V?

These targets need real cross-toolchains (`clang+lld` for native,
`mingw-w64` + static libcurl for Windows, `zig cc` for macOS / musl
/ glibc cross). None of these realistically fit into a Worker or
browser bundle today.

Three sensible policies:

**P1** — Drop cross-compile from the static playground. Surface a
banner: "Use the [container build](https://play.nurl-lang.org) for
non-wasm targets." The static deployment becomes a *wasm playground*,
which is what 95% of playground users want.

**P2** — Keep the existing container around purely for cross-compile,
but front it with the static UI. The container can scale to zero
(Cloudflare Containers `sleepAfter: 10m` already does this) and only
wakes when someone clicks "Build Linux".

**P3** — Pre-bake a small library of "example x target" binaries at
release time, served as flat files. No live cross-compile. Useful
for demo screenshots but not for editing.

P2 is the pragmatic recommendation: the static playground covers
hello-world / canvas / audio / wasm-only flows with no backend;
heavy cross-compile work falls back to the existing container which
already exists and is paid for.

---

## 5. Other static-friendly bits

These are easy wins regardless of which option we pick:

- **`/readme`, `/roadmap`, `/gotchas`, `/grammar`, `/license`.**
  Today these read files from `/opt/nurl/` on container boot and
  format as HTML. They could be pre-rendered into static `.html`
  files at build time and served from a CDN.
- **`/examples` and `/examples/<name>`.** Pre-render a JSON manifest
  + the raw `.nu` files at build time. No runtime needed.
- **`/stdlib-viewer`, `/tests-viewer`, `/stdlib/*path`, `/tests/*path`.**
  Same — flat-file browse-tree generated at release.
- **`/openapi.json`.** Today generated dynamically in NURL
  (main.nu:1118+). Trivial to dump to a static file at build time.
- **`/health`, `/targets`.** Trivial JSON; can be static for the
  S3 build. `/targets` is just an array of `{id, label, group,
  endpoint, runnable, notes}` and the front-end can ship it inline.
- **Monaco**. Already loaded from `cdn.jsdelivr.net` (static/index.
  html:197). No change needed.
- **`browser_wasi_shim`**. Already loaded from `esm.sh` (static/
  index.html:212). No change needed.

The MCP server (`POST /mcp`), OAuth stubs (`/register`, `/authorize`,
`/token`, `/.well-known/*`) and the artifact download endpoint
(`/download/...`) are inherently stateful or runtime-dynamic and
should stay on the container (or move to a dedicated Worker).

---

## 6. Recommended phased rollout

### Phase 1 — Quick win (S1, ~days)

Move static parts to Cloudflare Pages:
- Pre-render `/readme`, `/roadmap`, `/gotchas`, `/grammar`,
  `/license`, `/stdlib-viewer`, `/tests-viewer` from the repo at
  release time.
- Generate `/examples`, `/stdlib/*`, `/tests/*` manifests + flat
  files at release time.
- Serve `static/index.html` (the playground UI) from Pages.
- Leave all `/build*`, `/mcp`, OAuth endpoints on the existing
  container, called via `fetch('https://api.nurl-lang.org/build_wasm')`.

Net effect: the container handles only build + MCP traffic. Page
loads stop waking the container. Cold-start cost paid only on the
first build click.

### Phase 2 — Pure-static wasm build (S2, ~weeks)

1. Fold `prepare_ir_for_wasi` into `nurlc` as `--target=wasm32-wasi`
   (§3.4 option 3). One-time compiler change.
2. Decide linker strategy:
   - Fast path: bundle `wasm-tools merge` (or `walrus`) compiled to
     wasm (§3.5). ~1-3 MB extra.
   - Conservative path: ship a small `clang.wasm` build (§3.3.a) —
     larger but battle-tested.
3. Build the in-browser pipeline:
   - User clicks Build → fetch `nurlc.wasm` + `runtime.wasm.o` + linker
     from CDN (cache in IndexedDB)
   - Run `nurlc.wasm <src>` under `browser_wasi_shim` → IR text
   - Run linker → `.wasm` bytes
   - Hand to the existing `run()` path

After Phase 2, the wasm playground works offline. Cross-compile still
hits the container (policy P2).

### Phase 3 — Optional research arc (S3-strict)

- Implement a NURL-native wasm backend (§3.3.b). Removes the LLVM
  dependency from the playground entirely. Output of phase 2's
  Linker step becomes a single nurlc invocation.
- Implement a pure-NURL wasm linker (§3.5). Removes the last
  third-party wasm dependency.

Phase 3 is *not* a prerequisite; it is what gets us "no third-party
runtime, no large bundle, pure NURL all the way down". Treat it as
the long-term aspiration matching the project's self-hosting goals.

---

## 7. Decision matrix

|                         | Today | Phase 1 (S1) | Phase 2 (S2)         | Phase 3 (S3 strict) |
|-------------------------|-------|--------------|-----------------------|----------------------|
| Page load needs container | yes | **no**       | no                   | no                   |
| Hello-world wasm build needs container | yes | yes | **no**         | no                   |
| Cross-compile needs container | yes | yes      | yes                  | yes (or P3 prebuilds)|
| Toolchain bundle size in browser | 0 | 0          | 5-15 MB (fast) / 30-80 MB (conservative) | 1-5 MB |
| Offline playground      | no    | no           | **yes (after first build)** | yes              |
| New compiler work       | none  | none         | 1 nurlc flag         | NURL wasm backend + linker |
| Engineering effort      | -     | days         | weeks                | months               |
| Container cost reduction | none | ~80% (no UI traffic) | ~99% (only cross-compile) | 100% (container retired) |

---

## 8. Open questions

1. **Bundle size of nurlc.wasm.** Need to actually measure
   `./buildwasm.sh && wc -c nurlc.wasm` to validate the 5-15 MB
   estimate. The compiler is 11.5K LOC of NURL; with `-O2` it could
   be anywhere from 2 MB to 12 MB. If it lands closer to 12 MB, the
   in-browser-first-build penalty deserves a loading UI.
2. **Worker CPU budget.** Cloudflare Workers' free tier gives 10 ms
   CPU; paid gives 30 s. Need to time a representative build to
   know which tier the public playground needs.
3. **Linker choice.** `walrus` (Rust) vs. `wasm-tools` (Rust) vs.
   a NURL implementation. Picking one is a separate decision that
   doesn't block Phase 1.
4. **Asyncify-instrumented modules.** The canvas pipeline today
   relies on `wasm-opt --asyncify` (binaryen) being run server-side.
   `binaryen.js` exists and is well-supported; folding it into the
   browser build is straightforward but adds another ~1-2 MB to the
   bundle.
5. **Source privacy.** S2/S3 send the user's source to nobody. S1
   still sends it to the build endpoint. Worth a one-line note in
   the playground UI either way.

---

## 9. TL;DR

- **Phase 1 is a near-free win**: front-end + docs on Cloudflare
  Pages, container only for builds. Days of work.
- **Phase 2 is the real prize**: wasm builds entirely in-browser via
  `nurlc.wasm` (already exists) + a small wasm linker. Container
  remains *only* for cross-compile to Linux/Win/Mac/RISC-V. Weeks
  of work; the hard part is picking and integrating the linker.
- **Phase 3 (pure-NURL wasm backend + pure-NURL linker)** is the
  ideologically-pure endpoint that matches the project's
  self-hosting trajectory. Months of work, not a blocker for anything.

The single highest-leverage compiler change is **`nurlc
--target=wasm32-wasi`** (fold `prepare_ir_for_wasi` into the
compiler). It unlocks Phase 2 and is well-scoped on its own.
