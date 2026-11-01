### Changed

- **`fs_tempdir "" prefix` and `fs_tempfile "" prefix` create under the
  platform's temp directory** (Agora #322). An empty `dir` meant the
  current directory, so a program asking for scratch space wrote it into
  whatever directory it was started from: a checkout, a home directory, or
  `C:\Windows\System32` for a Windows service. It now means
  `env_temp_dir()` (`$TMPDIR` or `/tmp`; on Windows `%TMP%`, `%TEMP%`, …),
  as in Go's `os.MkdirTemp("", p)` and Python's `tempfile`. Pass `.` for
  the current directory. A program that relied on `""` creating in the
  current directory must now pass `.`.
