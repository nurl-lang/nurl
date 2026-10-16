# Rules → formal rules

Every ownership rule of [`docs/MEMORY.md`](../docs/MEMORY.md) and the
phase that formalizes it. A rule is **done** when its typing rule is
stated, used in the soundness proof, and every hole probe it is meant to
reject is mapped to it in [`corpus/map.tsv`](corpus/map.tsv).

| MEMORY.md | Rule | Phase | Formal rule | Status |
|---|---|---|---|---|
| §1, §7.6 | Single owner, drop flags, auto-drop | A1 | — | not started |
| §2.1 | Moves — use after move | A1 | — | not started |
| §2.1b | Releasing what the compiler releases | A1 | — | not started |
| §2.2 | Second names | A1 | — | not started |
| §2.3 | Stack references must not escape | A1 | — | not started |
| §2.4 | Exclusive access for `inout` arguments | A1 | — | not started |
| §2.5 | Iterator invalidation | A1 | — | not started |
| §2.6 | Loop-carried moves | A1 | — | not started |
| §2.7 | Escape through a callee | A1 | — | not started |
| §2.8 | Escape through a return | A1 | — | not started |
| §2.10 | Views end when their source may reallocate | A1 | — | not started |
| §2.12 | A stored value belongs to its owner | A1 | — | not started |
| §2.13 | A raw string in a value is a view | A1 | — | not started |
| §2.11, §7.5 | Closures hold their captures | A2 | — | not started |
| §7.2, §7.3 | Panics and the drop journal | A2 | — | not started |
| §7.7 | Reference-count cycles | A2 | — | not started |
| §6.5 | Threads: `Send`, `Sync`, `Arc`, `Mutex`, `Locked`, channels | A3 | — | not started |
| §3, §6.4 | `unsafe` boundary and the trusted base | B | — | not started |
