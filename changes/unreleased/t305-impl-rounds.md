### Performance

- **The ownership summaries settle without re-reading every implication on
  every round** (Agora #305). At the end of a module, nurlc runs its
  parked summary implications ("this parameter escapes if that callee's
  does") to a fixed point. Each round re-read every record: five words
  parsed and copied, the callee's sets looked up.
  - A chain of trait-object calls (dst_flagship's TlsTransport → NetTransport
    → NetDialer) settles one link per round, and that program took 23
    rounds over 600 KB of records.
  - Now each list is read once, and a round reads only the records whose
    callee gained a fact since the last read. The sets only grow, so every
    round ends in the same state, in the same number of rounds.
  - The resolvers also read the lists in place. Read through the symbol
    table, each list had been copied into the interner for the rest of the
    compile: 850 KB in a self-compile.
  - dst_flagship compiles in 5.1 % fewer instructions (16.42 G → 15.58 G),
    and a self-compile in 0.3 % fewer. Peak heap is the same for
    dst_flagship (+10 KB) and 1.05 MB lower for the self-compile.
  - Output is byte-identical (tools/tree_sweep.sh, 3612 files).
