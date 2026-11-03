### Fixed

- **A closure storing a join of its view parameter into a capture is
  refused** (Agora #448; probes closure_stores_a_join_of_*).
  `: s t ? c p `x`` followed by `= w @ V { t }`, with `w` captured, gave
  `w` a view of the caller's String that outlived it. The plain
  `: s t p` was refused (#332). The join is now too. A join of literals
  stays accepted.
