### Added

- **`nurlc --emit-core` passes the walk's ownership refusals and prints the
  walk's own summaries** (AGORA-859, preparing stage S2 of
  `docs/dev/PROPOSAL_CORE_IR.md`). Every ownership refusal the fused walk
  makes goes through one door (`own_die*`, `bck_emit_error`, `g_walk_owns`):
  under `--emit-core` it is let through, so a program the walk refuses
  reaches the IR whole and the reference checker decides it. New in the
  IR's text: `sum` lines (what the walk's summaries hold for each function,
  for a callee with no body, and for a generic's template), the type
  table's flags `d` (its drop may read its views), `h` (its copy is a
  share) and `t` (threads may use copies at once), and the function flags
  "crosses the raw boundary" (the raw-call rule's own answer) and "calls a
  foreign function". A body that falls off with a tail `?` / `??` value now
  has its `ret` in the IR. No behaviour changes without the flag.
  `docs/dev/CORE_IR.md` §2 and §6 describe the additions.
- `tools/ncore`: the reference checker's rules are listed in
  `tools/ncore/RULES.md`, each with where docs/MEMORY.md states it;
  `derive.py` answers for a library function whose body crosses the raw
  boundary from the walk's summaries; `run.py --clean` measures the rules
  on programs nurlc accepts.
