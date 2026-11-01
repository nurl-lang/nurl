### Added

- **`env_temp_dir()`: where temporary files go, on each platform's terms**
  (Agora #306, `stdlib/ext/env.nu`).
  - POSIX: `$TMPDIR` when set and non-empty, else `/tmp`.
  - Windows: what `GetTempPathW` answers, `%TMP%`, else `%TEMP%`, else
    `%USERPROFILE%`, else the Windows directory. `TMPDIR` is not read there,
    because Git Bash exports it as a POSIX path a native program cannot open.
  - The result is never empty and has no trailing separator. A drive or
    filesystem root is kept as it is.
  - docs/stdlib/fs.md shows it as the parent for `fs_tempdir`.

### Fixed

- **http_cli, nurlpkg and the test corpus use one answer for the temp
  directory** (Agora #306). They used three, and they disagreed.
  - http_cli read `TMPDIR`, then `TEMP`/`TMP`, then `/tmp`, on every
    platform. Under Git Bash on Windows that is an MSYS path.
  - nurlpkg fell back to the current directory on Windows.
  - A dozen corpus tests wrote under a hard-coded `/tmp`. On Windows that is
    `\tmp` on the current drive, which existed only when an earlier test
    happened to create it, so the outcome depended on test order.
  - All of them now ask `env_temp_dir`. The tests that still name `/tmp` are
    Linux-only (inotify, unix sockets, kTLS, symlinks), or never run their
    path (a compile-error test).
