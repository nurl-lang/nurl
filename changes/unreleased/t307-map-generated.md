### Changed

- **The hole-probe table is generated where it is read, not committed**
  (Agora #307). `formal/corpus/map.tsv` was derived entirely from the
  probes' `// map:` lines, yet every PR that added a probe regenerated
  and committed it: 19 commits touched it in a day, and two such PRs
  conflicted (github#1418). It is now git-ignored, and
  `tools/fuzz/holes/map.sh` (POSIX sh and awk, since build.sh needs no
  Python) writes it from the probes. build.sh writes it before anything
  reads it, `tools/install-toolchain.sh` and `.bat` write it into the
  prefix's `docs/formal/corpus/`, and the nurlapi image gets it from its
  builder's build.sh. webdocs' gen-formal-data reads it through map.sh.
  CI's shared-files job now runs `map.py --lint`, which checks that every
  probe has a well-formed `// map:` line, and requires map.sh and map.py
  to print the same table. A PR that adds a probe adds its `// map:` line
  and nothing else, so `map.py --write` is no longer a step.
