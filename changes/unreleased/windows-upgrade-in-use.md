### Fixed

- **`nurl upgrade` works on Windows again.** It always failed with
  `ForEach-Object : Cannot bind argument to parameter 'Path' because it is
  null`, leaving the toolchain unchanged. The installer
  (`tools/get-nurl.ps1`, bundled as `libexec\get-nurl.ps1`) renames
  whatever Windows will not delete, such as the `nurlpkg.exe` running the
  upgrade. It named that file by `$_.FullName` inside a `catch` block,
  where `$_` is the error record, so the rename got a `$null` path. The
  helper now loops with `foreach` over named items, and no longer tries to
  rename a file it has already moved.
- **`nurl upgrade` from PowerShell 7.** The installer runs under Windows
  PowerShell 5.1 (`powershell.exe`). Launched from pwsh 7 through cmd or
  `nurl.exe`, 5.1 inherited pwsh's `PSModulePath` and loaded PowerShell 7's
  `Microsoft.PowerShell.Utility`, which it cannot import, so the checksum
  step stopped at "`Get-FileHash` is not recognized". The installer now
  removes PowerShell 7's module directories from its own module path
  before it uses any module cmdlet. `tools/tests/test_installer_inuse.ps1`
  checks both cases on the Windows runner: it starts 5.1 from pwsh through
  cmd, against a prefix whose executables are running.
