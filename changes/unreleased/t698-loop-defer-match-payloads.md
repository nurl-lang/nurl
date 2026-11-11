### Fixed

- **A payload that a match arm binds as its own is kept for, and released
  after, a `;` defer of that arm inside a loop** (Agora #698,
  `compiler/nurlc.nu`). `?? ( make k ) { T t → { ; { … t … } } … }` in a
  loop body left every round's payload but the last unreleased, and a
  `break` in the arm above the `;` released the round's payload before
  the defer, armed in an earlier round, read it (heap-use-after-free). An
  arm's block that holds a `;` now keeps what is in sight at its head, as
  a loop with a defer does at its own; the payload an earlier round left
  to the cleanup is parked where the arm binds it again; and a match's
  temporary enum that a defer keeps is parked instead of released before
  the next round builds one.
