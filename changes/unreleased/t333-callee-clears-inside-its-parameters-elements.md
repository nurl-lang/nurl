### Fixed

- **A callee clearing inside its parameter's elements is summarised as
  dropping them** (Agora #333; probes callee_clears_*). These are the four
  forms of #315's drop half: through a local, directly, under a nested
  borrow, and through a struct element's field. #443 and #447 closed
  them; their probes now hold it.
