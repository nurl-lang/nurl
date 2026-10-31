### Fixed

- **The PowerShell runner controls no longer abort part-way through
  a CI run** (Agora #298). `tools/tests/test_compiler_runners.py` ran every
  pwsh with the job's own `~/.cache`, where pwsh keeps a startup profile
  (`powershell/StartupProfileData-NonInteractive`) that it reads when it
  starts and rewrites when it exits. Two pwsh processes exiting at once
  can leave that file torn (PowerShell/PowerShell#26528). In the failing
  run, every pwsh start after the control that runs two runners at once
  aborted with "The given assembly name was invalid": six controls failed,
  and the ones that expect a failure passed on the abort alone.
  Each test now has a cache of its own (`XDG_CACHE_HOME` under its
  temporary root), and each of the two concurrent runners has its own as
  well, so the controls are hermetic and leave the user's cache alone.
