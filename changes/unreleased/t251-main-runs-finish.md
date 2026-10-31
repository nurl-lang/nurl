### Changed

- **CI on main is no longer thrown away part-way** (Agora #251, part 3).
  20 of 35 push-to-main runs were cancelled by the next merge, which was a
  quarter of all ci.yml job-minutes and left those commits untested.
  ci.yml, windows-tests and macos-tests now cancel an in-progress run
  only on a PR branch. On main a started run finishes, and GitHub keeps
  only the newest pending run behind it. The release commit's macOS run
  is therefore not cancelled by a later merge once it has started.
