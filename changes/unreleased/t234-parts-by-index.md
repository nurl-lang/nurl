### Fixed

- **A split build finds its parts by index, so it can no longer lose one
  on FreeBSD** (Agora #234). `nurl.sh` and `split_equivalence.sh` listed
  the parts of a `--split` build with a glob (`PREFIX.[0-9]*.ll`), which
  reads the directory. While other files were created beside them (a
  parallel build, or clang's temp files), FreeBSD's UFS could move
  directory entries under a readdir in progress, and the glob skipped a
  part that existed the whole time. That part's code was then missing
  from the binary ("undefined symbol: main"), five times in CI on
  2026-10-31. Parts are now taken by index, 0 to N−1, in the order nurlc
  writes them, and stale parts are removed by name for every index nurlc
  can write (0–63).
