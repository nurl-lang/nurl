### Changed

- **`./build.sh` and `build.bat` fail when the compiler they build warns
  about its own source** (Agora #695). Stage 2 is the new compiler
  compiling `compiler/nurlc.nu`, the compile CI's
  `tools/tests/test_lsp_toolchain.py` requires to print nothing. nurlc's
  lints apply to new compiler code like to any other, and a warning there
  was a line in the build log of a build that passed; the pull request
  then failed three CI jobs a quarter of an hour later. The build now
  keeps stage 2's stderr and fails on a `warning:` in it, showing the
  warning and why — no extra compile, the same build time. A control in
  `tools/tests/test_build_failures.py` builds a copy of the tree whose
  `nurlc.nu` has such a warning and requires the build to fail with it.
