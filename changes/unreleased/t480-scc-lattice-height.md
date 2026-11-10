### Fixed

- **A recursion over many parameters is no longer refused for being
  long** (Agora #480). The borrow checker settles a recursive component's
  answers (what it keeps, hands back or holds) as a least fixed point and
  stopped after 16 rounds. A recursion that rotates 17 or more String
  parameters adds one word to its answer per round, so it never settled and
  was refused as if it might keep any of them. The rounds are now bounded
  by the height of the answers' lattice (the words the members' parameters
  can make), with a cost cap of 64 rounds (rotations up to about 60 parameters settle), past which the old, sound
  "may" answer stands. Compile times are unchanged (dst_flagship, the
  compiler itself).
