### Added

- **The verified checker covers A2 and A3 programs end to end, and nurlc's
  programs can be run through it** (Agora #970, #975). `formal/C` now
  decides A2's typing for every statement form a function body holds:
  - exits are carried as obligations (`C/A2Exit.lean`);
  - joins of `if` arms and loop rounds that end apart are checked by
    weakening (`C/A2Weaker.lean`);
  - destructor glue is decided, its `sink` alternative included;
  - whole programs are decided (`C.checked_program_safe2`), and A3's full
    claim for a checked program (`C.checked_claim_made_full`).

  `tools/ncore/tolean.py` translates nurlc's core IR (`--emit-core`) into A2,
  and `tools/ncore/certify.sh prog.nu` runs the verified checker on the
  result, printing `accepted`, `refused` or `unsupported: <construct>`.
  A construct the translation cannot render faithfully is reported, never
  guessed. Over `tools/fuzz/holes`, the checker accepts no probe that
  nurlc's map marks as rejected. The programs in `tools/ncore/certify/`
  each get nurlc's verdict.
