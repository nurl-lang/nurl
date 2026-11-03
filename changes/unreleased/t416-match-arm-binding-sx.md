### Fixed

- **A `??` used as a value keeps what a bare-binding arm views** (Agora
  #416; probes qq_value_arm_*). Take `= a ?? o { T m → @ W { `lit` } F →
  a }`, with `a` holding a view of a block local. The join's value was
  taken to view nothing, so `a` was kept past the local and read freed
  memory. The same held for a holder bound from such a join, a user enum's
  match, another holder as the arm, and a view pushed into a Vec through
  the join. Each arm of a `??` value is now taken by its operand, as a `?`
  arm is. A field arm (`F → . p vs`) records its own member path as a `?`
  arm does: before, it read a path left by an earlier field read, so a
  holder's field viewing a block local was missed and an unrelated one
  was refused.
