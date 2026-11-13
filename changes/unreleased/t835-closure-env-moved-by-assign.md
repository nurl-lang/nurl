### Fixed

- **A closure whose env was moved by `=` ends with its new owner**
  (Agora #835). After `= keep f`, keep holds f's environment; `= keep ( … )`
  released it, and a later `( f 1 )` ran on freed memory. f is now a borrow
  of keep: a call of f after keep changes is refused, one before it stays
  accepted.
