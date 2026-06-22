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

## Front-door wiring (nurlweb)

`nurl-lang.org` should serve the two installer scripts so the one-liners
work. Point:

- `https://nurl-lang.org/install.sh`  → `tools/get-nurl.sh`
- `https://nurl-lang.org/install.ps1` → `tools/get-nurl.ps1`

(either a static copy in the nurlweb deploy, or a redirect to the repo's
`raw.githubusercontent.com` path). `$NURL_INSTALL_BASE` overrides the
download base for internal mirrors / air-gapped installs.

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
