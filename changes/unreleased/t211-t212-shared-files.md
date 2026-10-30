### Changed

- **Pull requests no longer conflict over shared files: changelog
  fragments, hole probes with names, a generated probe table** (Agora
  #211, #212). On 2026-10-30 every parallel PR conflicted in the same
  places, though each changed different code. The places were the
  CHANGELOG's `[Unreleased]` section, the end of
  `formal/corpus/map.tsv`, about ten docs with hand-typed probe counts,
  and probe numbers claimed by post (h918–h923 were taken twice). Each
  rebase cost a CI run of about 40 minutes.
  - A changelog entry is now a fragment,
    `changes/unreleased/<task>.md`, and the release folds the fragments
    in with `tools/changelog.py fold X.Y.Z`.
  - The 930 hole probes are named for what they break
    (`hNNN_escape_inside_block_detached.nu` → `escape_inside_block_detached.nu`).
    Each probe carries its own row as a `// map: rule | phase | nurlc |
    old id | note` header line, and `tools/fuzz/holes/map.py` generates
    `map.tsv` from those lines, sorted by name. The old hNNN id stays in
    the `old_id` column, so `grep h941 formal/corpus/map.tsv` still finds
    a probe named in history.
  - The docs no longer carry probe counts; `map.py --counts` gives them.
  - A new CI job, *shared files are generated*, fails a PR that edits
    `[Unreleased]` or `map.tsv` by hand. Fragment-only changes skip the
    compiler jobs, as CHANGELOG.md edits already did.
