# Releasing the NURL toolchain

Distribution model (the rustup / Zig / Bun shape):

- **GitHub Releases** is the artifact store — one relocatable archive per
  target plus its `.sha256`.
- **`tools/get-nurl.sh` / `get-nurl.ps1`** is the front door, served from
  `nurl-lang.org` so users run `curl -fsSL https://nurl-lang.org/install.sh | sh`.
  It detects OS/arch, downloads the matching archive, verifies the
  checksum, and unpacks the toolchain into `~/.nurl`.
- **`reg.nurl-lang.org`** stays the *package* registry (libraries and
  programs). It does **not** distribute the toolchain — separate concern.

## Cutting a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release.yml` then builds, on a `v*` tag:

| Target | Runner | Archive |
|---|---|---|
| `linux-x86_64-glibc` | `ubuntu-latest` | `nurl-<tag>-linux-x86_64-glibc.tar.gz` |
| `linux-arm64-glibc`  | `ubuntu-24.04-arm` | `nurl-<tag>-linux-arm64-glibc.tar.gz` |
| `freebsd-x86_64`     | `ubuntu-latest` (FreeBSD 14 VM) | `nurl-<tag>-freebsd-x86_64.tar.gz` |
| `windows-x86_64`     | `windows-latest` | `nurl-<tag>-windows-x86_64.zip` |

Each job builds `nurlc` + `nurlpkg`, assembles the prefix with
`tools/install-toolchain.{sh,bat}` (relocatable shims), packages it, and
the final `release` job attaches every archive + `.sha256` to the GitHub
Release. Use the `workflow_dispatch` input for a dry run that builds the
artifacts without publishing.

An archive is just the `~/.nurl` layout (`bin/`, `build/`, `stdlib/`,
`nurl.{sh,bat}`, `env`) with shims that resolve their own location, so it
works wherever it is unpacked.

## Runtime dependencies (dynamic linking)

The toolchain binaries are built to depend on **libc only** — nothing else.
This is deliberate: a stray dependency on a library a fresh box lacks would
stop the toolchain dead before `main()` (the original bug: a `libpq.so.5`
NEEDED entry, inherited from the monolithic `runtime.o`, made `nurlpkg
install` fail on every machine without a Postgres client).

Two mechanisms keep it that way:

- Every link line passes **`-Wl,--as-needed`**, so a binary keeps a
  `DT_NEEDED` entry only for a library it actually references a symbol from.
  `runtime.o` still contains all the FFI back-ends (curl, OpenSSL, sqlite,
  libpq, zlib, zstd…), but LTO drops the code a given binary doesn't call,
  and `--as-needed` then drops the unreferenced libs. `nurlc` ends up
  needing only libc; `nurlpkg` likewise.
- **`nurlpkg`** reaches the registry through the system **`curl` binary**
  (`stdlib/ext/http_cli.nu`), not libcurl — the install one-liner already
  requires `curl`, so this adds no new requirement while removing the
  libcurl/OpenSSL link. Its only other real deps, **zlib + zstd** (package
  tarball (de)compression), are linked **statically** when a `.a` is
  available (`tools/nurlpkg/build.sh`). Net result: `nurlpkg` links libc
  only. On Windows it uses WinHTTP, no extra deps.
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
IR. Because `nurlpkg install <tool>` compiles the package from source, it
inherits this requirement — and on a fresh box that hit three walls in a
row: no `clang`; clang too old to parse nurlc's opaque-pointer IR; and clang
unable to read the release's newer LLVM bitcode.

The archive therefore **bundles a self-contained `zig`** (`zig cc`) as the
default backend — it carries its own modern LLVM (opaque pointers just
work), its own `lld` linker, and libc headers, so building needs **no system
compiler at all** and is immune to the box's LLVM version. The release
workflow downloads the per-arch zig (`Fetch bundled zig backend`) and
`install-toolchain.sh` stages it at `<prefix>/zig/`, exactly where
`nurl.sh` looks. Keep the bundled zig's LLVM ≥ the clang that built the
release (zig 0.13 → LLVM 18), so `zig cc -flto` can read the shipped
`runtime.o` bitcode. (~45 MB compressed per arch — the size cost of "just
works".)

`nurl.sh`'s compiler selection:

- Prefer the bundled zig (`<prefix>/zig/zig`, or `$NURL_ZIG`).
- Else fall back to a system clang: honour `$CLANG`, probe `clang` /
  `clang-<N>` / a clang-flavoured `cc`; pass `-Xclang -opaque-pointers` on
  clang 13/14; reject clang < 13; on no compiler at all, exit with install
  guidance instead of a raw `clang: command not found`.

`nurl.sh` also links a feature library (`-lcurl` / `-lssl` / `-lsqlite3` /
`-lpq` / `-lz` / `-lzstd`) **only when the emitted IR actually references
that back-end's symbols** — so a feature-free program (the common tool)
links against libc only and never demands a library the box may lack
(naming `-lpq` unconditionally previously made even a hello-world fail to
link where libpq was absent).

(A prebuilt-binary package channel — install a tool with no local compile at
all — remains the future bombproofing; see the registry roadmap.)

### glibc floor: the shipped binaries run on old distros too

The release runners have a recent glibc (2.39), and glibc is backward- but
**not** forward-compatible — so a `nurlc`/`nurlpkg` built there fails to
start on an older box (e.g. Raspberry Pi OS bullseye, glibc 2.31) with
`libc.so.6: version 'GLIBC_2.34' not found` (2.34 is where pthread folded
into libc). The release therefore **relinks** the shipped `nurlc` + `nurlpkg`
with the bundled zig against an **old glibc floor**
(`tools/relink-toolchain-portable.sh`, `zig cc -target <arch>-linux-gnu.2.17`)
— zig supplies the versioned glibc stubs, so we build on the modern runner
yet target ~glibc 2.14. This is possible because `nurlc` is libc-only and
`nurlpkg` adds only static zlib/zstd (ancient symbols). A successful relink
*caps* the floor at the target (the link fails outright if any code needs a
newer symbol), so portability is guaranteed by construction. The bundled
zig and the user programs it builds target the box's *native* glibc, so
those are unaffected.

## Front-door wiring (nurlweb)

`nurl-lang.org` should serve the two installer scripts so the one-liners
work. Point:

- `https://nurl-lang.org/install.sh`  → `tools/get-nurl.sh`
- `https://nurl-lang.org/install.ps1` → `tools/get-nurl.ps1`

(either a static copy in the nurlweb deploy, or a redirect to the repo's
`raw.githubusercontent.com` path). `$NURL_INSTALL_BASE` overrides the
download base for internal mirrors / air-gapped installs.

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
- The **Windows job is unverified on a real runner** — `build.bat` +
  `tools/nurlpkg/build.bat` + `install-toolchain.bat` exist but the
  toolchain has not yet been cut on `windows-latest`; exercise it with the
  `workflow_dispatch` dry run before announcing Windows support.
- macOS is not built yet (the installer rejects it with a clear message);
  add a `macos-14` (arm64) / `macos-13` (x86_64) matrix when wanted.
