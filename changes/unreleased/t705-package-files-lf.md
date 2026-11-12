### Fixed

- **A package's text files are LF in every checkout** (Agora #705).
  `nurlpkg publish` packs a package's files as the working copy holds
  them, and `.gitattributes` pinned LF only for `*.sh`, `*.nu`, Dockerfiles
  and the compiler goldens: with `core.autocrlf=true` a Windows checkout
  gave every other text file of a package — README, `nurl.toml`,
  CHANGELOG, line-based test data — CRLF line ends, so tokenizer 0.6.0 and
  nurldb 0.3.0 reached the registry with bytes the repository does not
  hold. Every text file under `packages/` is now `eol=lf`, the binary ones
  are named binary, and a control (on Linux and on the Windows runner)
  refuses a package file whose line ends follow the platform.
