### Changed

- **A binding's panic-journal registration ends inline** (Agora #283,
  part 1b). Bindings end in the reverse of their start, so the
  registration a scope exit forgets is the newest one on the slot stack.
  `nurl_journal_forget_slot` now pops it inline, with no call, unless
  something below it was ended out of order. On the handler-shaped
  microbenchmark this is another 6.4 % fewer instructions (219.2 M → 205.2 M),
  10.6 % with part 1.
