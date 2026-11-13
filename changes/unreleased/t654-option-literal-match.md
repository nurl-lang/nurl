### Fixed

- **A `??` over an option literal releases its payload** (Agora #654).
  `?? @ ?String { T ( string_clone s ) } { T q → … F → … }` — or a literal
  a binding was moved into — leaked the payload: the literal had taken it
  over, and the match, its last owner, released nothing. The literal owns
  its payload as a call's fresh result does: the arm's binding takes it
  over (to keep, hand on or drop), and an arm that does not bind it drops
  it.
