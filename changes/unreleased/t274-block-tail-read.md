### Fixed

- **A block whose tail is an owner already moved is refused** (Agora #274). `( consume a )` followed by `: String u ? c { … a } { b }`, by the same block as a `??` arm, or by `: String u { … a }` handed the freed `a` on and read it: a value block's tail reached no row the borrow checker looked at. The tail is now read where its block ends, from that block's own path, so a tail that only one path moved stays fine.
