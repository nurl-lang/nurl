# Releasing the NURL toolchain

Distribution model (the rustup / Zig / Bun shape):

- **GitHub Releases** is the artifact store — one relocatable archive per
  target plus its `.sha256` checksum and a detached minisign signature
  (`.minisig`, signed in the release workflow with `MINISIGN_SECRET_KEY`;
  the installers verify it against a pinned public key when `minisign` is
  available, and always verify the checksum fail-closed).
- **`tools/get-nurl.sh` / `get-nurl.ps1`** is the front door, served from
  `nurl-lang.org` so users run `curl -fsSL https://nurl-lang.org/install.sh | sh`.
  It detects OS/arch, downloads the matching archive, verifies the
  checksum, and unpacks the toolchain into `~/.nurl`.
- **`reg.nurl-lang.org`** stays the *package* registry (libraries and
  programs). It does **not** distribute the toolchain — separate concern.

## Cutting a release

A release is a PR first and a tag second. The tag is the *last* step,
because pushing one starts an irreversible chain — the release workflow
publishes archives and the web deploy re-reads the top `CHANGELOG.md`
section — and a tag on an unreviewed tree cannot be taken back, only
superseded.

### 1. Make `CHANGELOG.md` describe everything since the last tag

```bash
git fetch origin --tags
git log --oneline $(git describe --tags --abbrev=0)..origin/main
```

Read that list against the `[Unreleased]` section and close the gaps.
**This is not a formality** — merged PRs go undocumented routinely,
because the CHANGELOG entry is written by whoever remembers to write
one, and the release is where that gets noticed or never does. Ignore
the `bench: refresh measured numbers [skip ci]` commits; they are
automation.

Then rename `[Unreleased]` to `[X.Y.Z] — YYYY-MM-DD`, newest first.
Choose the number the usual way: a new capability is a minor bump, a
fix-only run is a patch. The version is read from this heading by
`tools/gen-site-facts.sh`, so the heading IS the released version as far
as `nurl-lang.org` is concerned.

### 2. Check `ROADMAP.md` and `docs/`

Anything the release *finishes* or *changes the shape of* is likely
described in prose somewhere that no test covers:

- `ROADMAP.md` — a milestone this release closed still listed as future
  work is the most common miss.
- `docs/` — `PLATFORMS.md`, `LIMITATIONS.md`, `NETWORKING.md`,
  `MEMORY.md`, `TOOLING.md`, `spec.md`. A limitation that has stopped
  being true is worse than one that was never written down: it is
  actively wrong, and the `docs/` tree ships **inside the toolchain
  archive** (the nurl-mcp `nurl_docs` tool serves it), so a stale
  sentence is installed on every user's machine.

### 3. Branch and PR

```bash
git switch -c Release-vX.Y.Z
git commit -am "Release vX.Y.Z"
gh pr create --title "Release vX.Y.Z" --fill
```

Same review and same CI as any other change — Windows, FreeBSD, arm64,
ASan and the unikernel gates all run.

### 4. Tag, once it is merged and CI is green on `main`

```bash
git switch main && git pull --ff-only
git tag vX.Y.Z
git push origin vX.Y.Z
```

Tag the merge commit on `main`, never the branch: the tag is what users
download, and it should name a commit that passed CI in the state it
was merged.

`.github/workflows/release.yml` then builds, on a `v*` tag:

| Target | Runner | Archive |
|---|---|---|
| `linux-x86_64-glibc` | `ubuntu-latest` | `nurl-<tag>-linux-x86_64-glibc.tar.gz` |
| `linux-arm64-glibc`  | `ubuntu-24.04-arm` | `nurl-<tag>-linux-arm64-glibc.tar.gz` |
| `freebsd-x86_64`     | `ubuntu-latest` (FreeBSD 14 VM) | `nurl-<tag>-freebsd-x86_64.tar.gz` |
| `windows-x86_64`     | `windows-latest` | `nurl-<tag>-windows-x86_64.zip` |

Each job builds `nurlc` + `nurlpkg`, assembles the prefix with
`tools/install-toolchain.{sh,bat}` (relocatable shims), packages it, and
the final `release` job signs and attaches the produced archives +
`.sha256` + `.minisig` to the GitHub Release. The FreeBSD leg is
**best-effort** (`continue-on-error`): a release can ship without the
FreeBSD archive if that VM build fails. Use the `workflow_dispatch` input
for a dry run that builds the artifacts without publishing.

An archive is just the `~/.nurl` layout (`bin/`, `build/`, `stdlib/`,
`docs/`, `nurl.{sh,bat}`, `env`) with shims that resolve their own
location, so it works wherever it is unpacked. `docs/` is the prose tree
the nurl-mcp `nurl_docs` tool serves, so an installed toolchain answers
questions about ownership, crypto and platforms without the network.

## Runtime dependencies (dynamic linking)

The toolchain binaries are built to depend on **libc only** — nothing else.
This is deliberate: a stray `NEEDED` entry for a library a fresh box lacks
would stop the toolchain dead before `main()`.

Two mechanisms keep it that way:

- Every link line passes **`-Wl,--as-needed`**, so a binary keeps a
  `DT_NEEDED` entry only for a library it actually references a symbol from.
  `runtime.o` still contains all the FFI back-ends (curl, OpenSSL, sqlite,
  libpq…), but LTO drops the code a given binary doesn't call,
  and `--as-needed` then drops the unreferenced libs. `nurlc` ends up
  needing only libc; `nurlpkg` likewise.
- **`nurlpkg`** reaches the registry through the system **`curl` binary**
  (`stdlib/ext/http_cli.nu`), not libcurl — the install one-liner already
  requires `curl`, so this adds no new requirement while removing the
  libcurl/OpenSSL link. Package tarball (de)compression — gzip and zstd
  alike — is pure NURL (`stdlib/std/deflate.nu`, `stdlib/std/zstd.nu`), so
  there is nothing left to link. Net result: `nurlpkg` links libc only. On
  Windows it uses WinHTTP, no extra deps.
- A user program still links additional libraries on demand — only when it
  imports the matching module — via the `stdlib/runtime.<feature>`
  sentinels and the same `--as-needed` link (`nurl.sh`/`nurl.bat`). A
  program that imports nothing DB-related never inherits libpq/sqlite.

`tools/get-nurl.sh` smoke-tests the unpacked `nurlc`/`nurlpkg` (they must at
least load) and, on a missing-shared-library loader error, prints the
offending `.so` plus a package-manager hint instead of failing cryptically
at first use.

### Building a program: the bundled zig backend

Running the toolchain (e.g. `nurlc`) needs nothing but libc, but *building*
a program does: `nurlc` emits LLVM IR (`.ll`), which an LLVM compiler lowers
to a native binary and links against `runtime.o`. gcc/cc cannot consume LLVM
IR, the compiler must be new enough to parse opaque-pointer IR (LLVM 15+),
and it must be able to read the release's `runtime.o` bitcode. Because
`nurlpkg install <tool>` compiles the package from source, it inherits all
of this.

The archive therefore **bundles a self-contained `zig`** (`zig cc`) as the
default backend — it carries its own modern LLVM (opaque pointers just
work), its own `lld` linker, and libc headers, so building needs **no system
compiler at all** and is immune to the box's LLVM version. The release
workflow downloads the per-arch zig (`Fetch bundled zig backend`) and
`install-toolchain.sh` stages it at `<prefix>/zig/`, exactly where
`nurl.sh` looks. Keep the bundled zig's LLVM ≥ the clang that built the
release (zig 0.16 → LLVM 21), so `zig cc -flto` can read the shipped
`runtime.o` bitcode. (~45 MB compressed per arch — the size cost of "just
works".)

`nurl.sh`'s compiler selection:

- Prefer the bundled zig (`<prefix>/zig/zig`, or `$NURL_ZIG`).
- Else fall back to a system clang: honour `$CLANG`, probe `clang` /
  `clang-<N>` / a clang-flavoured `cc`; reject clang < 15 (the minimum —
  LLVM 15 emits opaque-pointer IR by default); on no compiler at all, exit
  with install guidance instead of a raw `clang: command not found`.

`nurl.bat`'s selection follows the same shape, with one Windows-only
complication: **the two compilers do not share an ABI.** A system clang
targets MSVC; the bundled `zig cc` targets `x86_64-windows-gnu`. An object
built for one cannot be linked by the other — a clang-built `runtime.o`
references `_setjmp`, `__chkstk` and `_fltused`, and MinGW's CRT provides
none of them. So `build.bat` produces **two** runtime objects, `runtime.o`
(clang/MSVC) and `runtime.mingw.o` (zig/MinGW), and the driver links
whichever matches the compiler it selected. Both ship in the archive;
`install-toolchain.bat` copies the whole `stdlib` tree, so no packaging
step needs to know about it.

Consequences worth knowing:

- The zig fetch must come **before** `build.bat` in any workflow that
  builds a shippable prefix, or the MinGW object is silently absent and
  everything still passes on a runner that has LLVM installed.
- Two things stay MSVC-only, because the library each needs is an MSVC
  import lib: the **canvas** FFI (`canvas.o` + `SDL2.lib`) and **real GPU
  compute** (`cuda.lib` / `nvrtc.lib` from a CUDA Toolkit). Canvas needs
  clang and the driver refuses with that message rather than leaving it
  to the linker; `gpu` instead falls through to the driverless stubs and
  runs on the CPU backend, so a program that only pulls `gpu` in
  transitively builds under the bundled zig. Compression is unaffected —
  gzip, deflate and zstd are all pure NURL.

`nurl.sh` also links a feature library (`-lcurl` / `-lssl` / `-lsqlite3` /
`-lpq`) **only when the emitted IR actually references
that back-end's symbols** — so a feature-free program (the common tool)
links against libc only and never demands a library the box may lack.

(A prebuilt-binary package channel — install a tool with no local compile at
all — remains the future bombproofing; see the registry roadmap.)

### glibc floor: the shipped binaries run on old distros too

The release runners have a recent glibc (2.39), and glibc is backward- but
**not** forward-compatible — so a `nurlc`/`nurlpkg` built there fails to
start on an older box (e.g. Raspberry Pi OS bullseye, glibc 2.31) with
`libc.so.6: version 'GLIBC_2.34' not found` (2.34 is where pthread folded
into libc). The release therefore **relinks** the shipped `nurlc` + `nurlpkg`
with the bundled zig against an **old glibc floor**
(`tools/relink-toolchain-portable.sh`, `zig cc -target <arch>-linux-gnu.2.28`
by default) — zig supplies the versioned glibc stubs, so we build on the
modern runner yet target glibc 2.28. This is possible because `nurlc` and
`nurlpkg` are both libc-only. A successful relink
*caps* the floor at the target (the link fails outright if any code needs a
newer symbol), so portability is guaranteed by construction. The bundled
zig and the user programs it builds target the box's *native* glibc, so
those are unaffected.

## Front-door wiring (nurlweb)

`nurl-lang.org` serves the two installer scripts so the one-liners work:
the web deploy's `predeploy` hook (`nurlweb/package.json`,
`sync-installers`) copies `tools/get-nurl.sh` → `nurlweb/public/install.sh`
and `tools/get-nurl.ps1` → `nurlweb/public/install.ps1` before
`wrangler deploy`. **`tools/get-nurl.{sh,ps1}` are the canonical sources**
— edit those, never the `public/` copies, or the next deploy overwrites
the edit. `$NURL_INSTALL_BASE` overrides the download base for internal
mirrors / air-gapped installs.

Pushing a `v*` tag also fires `.github/workflows/web-deploy.yml`, which
runs `npm run deploy` in `nurlweb/`. Its `predeploy` hook regenerates the
landing-page facts (`tools/gen-site-facts.sh`, version sourced from the top
`CHANGELOG.md` section) and re-syncs the installer scripts before
`wrangler deploy`, so `nurl-lang.org` refreshes its version and counts in
lockstep with each release. The job is a green no-op when
`CLOUDFLARE_API_TOKEN` is unset (forks), and can also be run manually from
the Actions tab.

## Status / caveats

- The Linux client path (download → verify → unpack → run) is verified
  end to end against a local mirror; the relocatable prefix is verified by
  moving it after install.
- The Windows release job builds with `--no-tests`, but Windows is not
  untested: the separate `windows-tests` workflow runs `build.bat` — the
  bootstrap fixed point plus the full Windows golden corpus
  (`compiler/tests/outputs-windows/`, via `run_tests.ps1`) — on every
  push to `main` and every PR.
- The FreeBSD release leg is best-effort (`continue-on-error`); a release
  can ship without the FreeBSD archive.
- macOS ships no release artifact yet — the installer rejects Darwin with a
  clear message and the install route stays build-from-source. It is *not*
  untested: the `macos-tests` workflow runs `./build.sh` on Apple Silicon
  (bootstrap fixed point + the full corpus against the same `outputs/`
  goldens as Linux) on every push to `main` and every PR. Adding a release
  leg means `macos-14` (arm64) only — the Intel `macos-13` image never left
  GitHub's queue across ten attempted runs, which is why that leg was
  removed rather than left permanently pending (see
  [`docs/PLATFORMS.md`](docs/PLATFORMS.md)).
