### Changed

- **ci.yml answers the merge queue** (Agora #136, phase 1). With `main`'s
  ruleset requiring the merge queue, a green PR is queued (`gh pr merge
  <N> --squash --auto`) instead of rebased and re-run each time `main`
  moves. The queue tests `main` plus the queued PRs as one commit,
  merges exactly that commit, and splits a failing group to find the
  culprit. In a `merge_group` run every job runs, whatever the paths,
  and the golden-twin gate diffs against the group's base. The required
  checks (build + corpus, FreeBSD, ASan + UBSan) all live in ci.yml, so
  windows-tests and macos-tests stay out of the queue (macOS runners are
  too scarce to gate it).
