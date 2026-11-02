### Fixed

- **A loop that may run no time keeps what its holders viewed when it was
  entered** (Agora #413; probes *_in_a_loop_*). Take a holder given a view
  of a block local, then a new value inside a loop with a scratch owner.
  After the loop, the holder was taken to view nothing, because the loop's
  last check walked the body once and kept its result. On a run that skips
  the loop, the holder still viewed the local, and reading it after the
  block read freed memory. This held for a struct holder, a Vec holder,
  one returned from the function, and an `inout` holder at the exit. The
  dependencies the loop was entered with are now joined back after that
  walk, as its borrow sources are.
