### Fixed

- **Nested `~` loops compile in linear time** (Agora #210). The borrow
  checker walked a loop body three or four times at every level of
  nesting, so compile time grew about ×3 per nested `~`: 15 levels took
  32 s and 20 passed the playground's 120 s timeout. A walk reads facts
  earlier walks wrote beside the state string, so those walks could not
  simply be dropped. A loop's fixpoint now compares the facts too,
  through a digest of the borrow checker's tables that every write keeps
  in step. Once the next walk would repeat one already made (same state,
  same facts: no change, or a cycle such as a swap of two loop-carried
  bindings), it stops, and the back and verification walks that would
  repeat it are skipped. 200 nested loops compile in under 0.1 s. Every
  file in the tree compiles byte-identically to before. The self-compile
  runs 3.4 % fewer instructions. The pending-lend lists are sets now; an
  entry each walk added again grew them without end.
  `tools/check_bck_writes.sh` (CI) keeps every write to those tables
  going through the digest.
