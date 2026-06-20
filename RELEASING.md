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

The shipped binaries link a few system libraries dynamically. `glibc`
targets assume a normal desktop/server distro where these are present:

- **`nurlpkg`** needs **libcurl** + **OpenSSL** for registry HTTPS on Linux
  (Windows uses WinHTTP, no extra deps).
- A user program links additional libraries only when it imports the
  matching module (`nurl.sh`/`nurl.bat` add them on demand from the
  `stdlib/runtime.<feature>` sentinels shipped in the archive).

A fully self-contained (statically linked) build is a possible follow-up.

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
