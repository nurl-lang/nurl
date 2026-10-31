### Changed

- **The macOS gate runs on `macos-15`** (Agora #302). GitHub retires the
  `macos-14` image on 2026-11-02, and its scheduled brownouts were
  already cancelling the macos-tests runs on `main`. From that date the
  job, and with it release.yml's `verify-ci`, which waits for a green
  macos-tests run on the tagged commit, could never have passed. The job
  is pinned to `macos-15` (Apple Silicon), not `macos-latest`, because
  the image decides which macOS and which Xcode SDK the gate links
  against; it still builds with Homebrew LLVM. docs/PLATFORMS.md now
  names macOS 15 as the tested release.
