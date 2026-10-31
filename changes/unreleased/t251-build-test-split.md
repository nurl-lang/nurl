### Changed

- **CI's longest job runs as three jobs at once** (Agora #251, part 2).
  `build + bootstrap fixed point + test corpus` took 34 minutes (p50) and
  was the critical path of every PR. It is now three parallel jobs:
  - `build-corpus` runs ./build.sh: the bootstrap fixed point and the
    test corpus.
  - `build-gates` and `build-gates-2` each build the toolchain with
    `--no-tests` and run the gates that used to follow it: every gate,
    unchanged and in the same order.
  A fourth job under the old name passes only when all three passed, so
  the required check and the merge queue see the same name, with nothing
  dropped or loosened.
