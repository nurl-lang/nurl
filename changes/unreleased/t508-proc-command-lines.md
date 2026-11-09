### Added

- **`proc_command_lines`** (Agora #508, stdlib/std/process.nu): every live
  process's command line this one may read, as `ps` and Task Manager show
  it, one String per process. It is read natively: /proc/<pid>/cmdline on
  Linux, a Toolhelp32 snapshot plus NtQueryInformationProcess on Windows
  (which needs only PROCESS_QUERY_LIMITED_INFORMATION). It is None where
  the platform does not say (macOS, the BSDs, wasm, the unikernel). The
  runtime answers it (`nurl_proc_cmdlines`).

### Fixed

- **The Windows CI flake in `pkg_publish_argv_redact`** (Agora #508). The
  test inspects the live curl while its server holds the exchange open,
  and on Windows it asked PowerShell + WMI for the process list. On a
  loaded runner that cold start outlasted curl's 30 s stall window, and the
  first request failed with PubTimeout. It now calls `proc_command_lines`.
  On a 16-core desktop the scan takes 7–10 ms idle and 0.25–0.32 s with
  every core busy, against 2.9 s for PowerShell under the same load. The
  whole test takes 0.34 s instead of 2.05 s. A control that puts the token
  into curl's argv still fails the test (`inspect=1` on every exchange).
